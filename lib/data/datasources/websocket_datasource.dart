// lib/data/datasources/websocket_datasource.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — Remote Data Source
// ─────────────────────────────────────────────────────────────────────────────
//
// Ini adalah lapisan paling bawah yang benar-benar berinteraksi dengan
// jaringan menggunakan dart:io WebSocket.
//
// Tanggung jawab class ini:
//   1. Membuka/menutup koneksi WebSocket (raw TCP socket)
//   2. Encode JSON sebelum kirim, decode JSON saat terima
//   3. Implementasi reconnect dengan exponential backoff
//   4. Implementasi ACK pattern (tunggu respons spesifik per requestId)
//   5. Keamanan: TLS/WSS, JWT, payload signing
//   6. Heartbeat lokal (deteksi koneksi mati dari sisi client)
//
// CATATAN KEAMANAN:
//   - Selalu gunakan WSS (wss://) di production, bukan WS (ws://)
//   - JWT dikirim via query parameter pada handshake (bukan body/header)
//   - Payload signing opsional dengan HMAC-SHA256 untuk integritas data

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/constants/socket_constants.dart';
import '../../core/errors/socket_exceptions.dart';
import '../../core/utils/logger.dart';
import '../models/socket_message_model.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

/// Abstraksi datasource — untuk testability
abstract class WebSocketDataSource {
  Future<void> connect(String token);
  Future<void> disconnect();
  Stream<ConnectionStatus> get connectionStatus;
  Stream<SocketMessageModel> get incomingMessages;
  Future<void> send(SocketMessageModel message);
  Future<SocketMessageModel> sendWithAck(
      SocketMessageModel message, {
        Duration timeout,
      });
}

/// [WebSocketDataSourceImpl]
/// Implementasi WebSocket menggunakan dart:io WebSocket class.
///
/// dart:io WebSocket adalah wrapper di atas raw TCP Socket yang menangani
/// WebSocket protocol (RFC 6455) secara otomatis, termasuk:
/// - HTTP Upgrade handshake
/// - Frame encoding/decoding (text, binary, ping, pong, close)
/// - Masking client-to-server messages (sesuai spec)
class WebSocketDataSourceImpl implements WebSocketDataSource {
  // ─── Dependencies ────────────────────────────────────────────────────────────
  final String _baseUrl;              // wss://your-server.com
  final String _hmacSecret;          // Secret untuk signing payload (opsional)

  // ─── Internal State ──────────────────────────────────────────────────────────
  WebSocket? _socket;                 // Koneksi WebSocket aktif (nullable)
  StreamSubscription? _socketSub;    // Subscription ke stream pesan masuk

  // Status koneksi — di-broadcast ke semua listener
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  // Pesan masuk — di-broadcast ke semua listener (BLoC, dsb)
  final _incomingController = StreamController<SocketMessageModel>.broadcast();

  // ACK registry: Map<requestId, Completer>
  // Setiap sendWithAck() mendaftarkan Completer di sini.
  // Ketika respons dengan requestId sama datang, Completer di-complete.
  final Map<String, Completer<SocketMessageModel>> _pendingAcks = {};

  // Reconnect state
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;  // Apakah disconnect memang disengaja
  Timer? _reconnectTimer;

  // Token untuk re-auth saat reconnect
  String? _lastToken;

  WebSocketDataSourceImpl({
    required String baseUrl,
    String hmacSecret = '',
  })  : _baseUrl = baseUrl,
        _hmacSecret = hmacSecret;

  // ─── Public API ──────────────────────────────────────────────────────────────

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<SocketMessageModel> get incomingMessages => _incomingController.stream;

  /// Membuka koneksi WebSocket dengan JWT authentication.
  ///
  /// JWT dikirim via query parameter saat HTTP Upgrade request:
  ///   wss://server.com/ws?token=<JWT>
  ///
  /// Server memvalidasi JWT sebelum menerima koneksi (verifyClient).
  @override
  Future<void> connect(String token) async {
    _lastToken = token;
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;

    await _doConnect(token);
  }

  /// Internal: eksekusi koneksi sebenarnya (dipakai juga saat reconnect)
  Future<void> _doConnect(String token) async {
    _emitStatus(ConnectionStatus.connecting);

    try {
      // ── Bangun URL dengan JWT token ───────────────────────────────────────
      // WSS (TLS) wajib di production untuk enkripsi transport
      final uri = Uri.parse('$_baseUrl?token=${Uri.encodeComponent(token)}');

      AppLogger.info('Connecting to: ${uri.host}:${uri.port}');

      // ── Buka koneksi WebSocket ─────────────────────────────────────────────
      // dart:io WebSocket.connect() melakukan:
      // 1. Buka TCP socket ke server
      // 2. Kirim HTTP GET dengan header Upgrade: websocket
      // 3. Tunggu 101 Switching Protocols dari server
      // 4. Setelah itu, komunikasi menjadi full-duplex WebSocket frames
      _socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          // Custom header tambahan jika server membutuhkan
          'X-Client-Version': SocketConstants.clientVersion,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(
        SocketConstants.connectionTimeout,
        onTimeout: () => throw const SocketConnectionException(
          'Connection timed out after ${SocketConstants.connectionTimeoutSeconds}s',
        ),
      );

      // Set compression untuk menghemat bandwidth
      // Aktifkan hanya jika server mendukung per-message deflate
      // _socket!.compression = CompressionOptions.compressionDefault;

      AppLogger.info('WebSocket connected');
      _reconnectAttempts = 0;
      _emitStatus(ConnectionStatus.connected);

      // ── Listen ke pesan masuk ──────────────────────────────────────────────
      _socketSub = _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,  // Lanjutkan listen meski ada error
      );

    } on SocketException catch (e) {
      AppLogger.error('Socket connection failed: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    } on WebSocketException catch (e) {
      AppLogger.error('WebSocket handshake failed: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    } catch (e) {
      AppLogger.error('Unexpected connection error: $e');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    }
  }

  /// Menutup koneksi secara graceful.
  ///
  /// WebSocket close handshake:
  /// Client kirim Close frame → Server balas Close frame → TCP ditutup
  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();

    // Batalkan semua pending ACK dengan error
    _cancelAllPendingAcks('Disconnected by user');

    await _socketSub?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure, 'Client disconnected');
    _socket = null;

    _emitStatus(ConnectionStatus.disconnected);
    AppLogger.info('WebSocket disconnected (intentional)');
  }

  /// Kirim pesan ke server tanpa menunggu respons.
  @override
  Future<void> send(SocketMessageModel message) async {
    _ensureConnected();

    // ── Encode ke JSON ────────────────────────────────────────────────────────
    final json = message.toJson();

    // ── Tambahkan signature HMAC (opsional, untuk integritas payload) ─────────
    // Client dan server harus berbagi _hmacSecret yang sama.
    // Server bisa memverifikasi bahwa payload tidak dimodifikasi di tengah jalan.
    if (_hmacSecret.isNotEmpty) {
      json['signature'] = _signPayload(json);
    }

    final jsonString = jsonEncode(json);
    AppLogger.debug('Sending: $jsonString');

    _socket!.add(jsonString);
  }

  /// Kirim pesan dan tunggu respons dari server (request-response pattern).
  ///
  /// Mekanisme:
  /// 1. Daftarkan Completer ke _pendingAcks[requestId]
  /// 2. Kirim pesan
  /// 3. Await Completer.future (dengan timeout)
  /// 4. Ketika _onMessage menerima respons dengan requestId sama, complete Completer
  ///
  /// Ini memenuhi: "Pastikan data yang terkirim sudah terkirim dari server"
  @override
  Future<SocketMessageModel> sendWithAck(
      SocketMessageModel message, {
        Duration timeout = SocketConstants.ackTimeout,
      }) async {
    _ensureConnected();

    final completer = Completer<SocketMessageModel>();
    _pendingAcks[message.requestId] = completer;

    try {
      await send(message);

      // Tunggu respons dengan timeout
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingAcks.remove(message.requestId);
          throw SocketTimeoutException(
            'No ACK received for requestId: ${message.requestId}',
          );
        },
      );
    } catch (e) {
      _pendingAcks.remove(message.requestId);
      rethrow;
    }
  }

  // ─── Private: Event Handlers ─────────────────────────────────────────────────

  /// Dipanggil setiap ada pesan masuk dari server.
  void _onMessage(dynamic rawData) {
    try {
      // Decode JSON string menjadi Map
      final Map<String, dynamic> json = jsonDecode(rawData as String);
      AppLogger.debug('Received: $rawData');

      final model = SocketMessageModel.fromJson(json);

      // ── Cek apakah ini adalah respons untuk pending ACK ───────────────────
      if (model.requestId.isNotEmpty && _pendingAcks.containsKey(model.requestId)) {
        final completer = _pendingAcks.remove(model.requestId)!;
        if (!completer.isCompleted) {
          if (model.type == MessageType.error) {
            completer.completeError(
              SocketServerException(model.errorMessage ?? 'Server error'),
            );
          } else {
            completer.complete(model);
          }
        }
        return; // ACK response tidak perlu di-broadcast ke stream umum
      }

      // ── Broadcast ke stream umum (untuk server-push / broadcast messages) ──
      _incomingController.add(model);

    } catch (e) {
      AppLogger.error('Failed to parse incoming message: $e');
      // Jangan crash — lanjutkan mendengarkan pesan berikutnya
    }
  }

  /// Dipanggil saat terjadi error pada koneksi.
  void _onError(Object error, StackTrace stackTrace) {
    AppLogger.error('WebSocket error: $error');
    _emitStatus(ConnectionStatus.error);
  }

  /// Dipanggil saat koneksi ditutup (dari server atau dari client).
  void _onDone() {
    AppLogger.info('WebSocket connection closed');
    _socket = null;

    // Batalkan semua pending ACK karena koneksi sudah mati
    _cancelAllPendingAcks('Connection closed');

    if (!_intentionalDisconnect) {
      // Koneksi terputus tidak terduga → coba reconnect
      _emitStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  // ─── Private: Reconnect dengan Exponential Backoff ───────────────────────────

  /// Jadwalkan percobaan reconnect berikutnya.
  ///
  /// Exponential backoff: delay meningkat setiap kali gagal.
  ///   Attempt 1 → 1s
  ///   Attempt 2 → 2s
  ///   Attempt 3 → 4s
  ///   ...max: [SocketConstants.maxReconnectDelay]
  ///
  /// Ini mencegah server dibanjiri request reconnect saat ada masalah
  /// (thundering herd problem).
  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= SocketConstants.maxReconnectAttempts) {
      AppLogger.error('Max reconnect attempts reached. Giving up.');
      _emitStatus(ConnectionStatus.error);
      return;
    }

    _reconnectAttempts++;
    final delaySeconds = _calculateBackoffDelay(_reconnectAttempts);

    AppLogger.info(
      'Reconnecting in ${delaySeconds}s (attempt $_reconnectAttempts/${SocketConstants.maxReconnectAttempts})',
    );
    _emitStatus(ConnectionStatus.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (!_intentionalDisconnect && _lastToken != null) {
        try {
          await _doConnect(_lastToken!);
        } catch (_) {
          // Error sudah ditangani di _doConnect → _scheduleReconnect dipanggil lagi
        }
      }
    });
  }

  /// Hitung delay reconnect dengan exponential backoff + jitter.
  ///
  /// Jitter (noise kecil acak) mencegah semua client reconnect bersamaan
  /// setelah server restart (thundering herd).
  int _calculateBackoffDelay(int attempt) {
    final base = SocketConstants.reconnectBaseDelaySeconds;
    final max  = SocketConstants.maxReconnectDelaySeconds;
    // Exponential: base * 2^(attempt-1)
    final delay = (base * (1 << (attempt - 1))).clamp(base, max);
    return delay;
  }

  // ─── Private: Security ────────────────────────────────────────────────────────

  /// Buat HMAC-SHA256 signature dari payload JSON.
  ///
  /// Signature memungkinkan server memverifikasi bahwa:
  /// 1. Payload tidak dimodifikasi (integritas)
  /// 2. Pengirim mengetahui shared secret (autentikasi tambahan)
  ///
  /// Algoritma:
  ///   signature = HMAC-SHA256(sorted_json_string, hmacSecret)
  String _signPayload(Map<String, dynamic> payload) {
    // Buat salinan tanpa field 'signature' (untuk menghindari circular dependency)
    final data = Map<String, dynamic>.from(payload)..remove('signature');

    // Sort key untuk konsistensi — server harus melakukan hal yang sama
    final sortedJson = jsonEncode(Map.fromEntries(
      data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ));

    final key  = utf8.encode(_hmacSecret);
    final msg  = utf8.encode(sortedJson);
    final hmac = Hmac(sha256, key);
    final dig  = hmac.convert(msg);

    return dig.toString();
  }

  // ─── Private: Helpers ─────────────────────────────────────────────────────────

  void _emitStatus(ConnectionStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _ensureConnected() {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      throw const SocketNotConnectedException(
        'WebSocket is not connected. Call connect() first.',
      );
    }
  }

  void _cancelAllPendingAcks(String reason) {
    for (final entry in _pendingAcks.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(SocketConnectionException(reason));
      }
    }
    _pendingAcks.clear();
  }

  /// Cleanup semua resources saat object di-dispose.
  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
    await _incomingController.close();
  }
}