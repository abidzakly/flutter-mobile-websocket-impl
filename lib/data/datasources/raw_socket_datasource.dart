// lib/data/datasources/raw_socket_datasource.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — Raw TCP Socket Data Source
// ─────────────────────────────────────────────────────────────────────────────
//
// ★ PERBEDAAN UTAMA DARI WEBSOCKET ★
//
// WebSocket:
//   dart:io WebSocket.connect()
//   → HTTP GET dengan header "Upgrade: websocket"
//   → Server balas "101 Switching Protocols"
//   → Komunikasi via WebSocket frames (ada header frame: FIN bit, opcode,
//     masking key, payload length — total overhead 2–10 byte per frame)
//   → Autentikasi lewat query param di URL (?token=...)
//
// Raw TCP Socket (implementasi ini):
//   dart:io Socket.connect()
//   → Langsung buka koneksi TCP (3-way handshake: SYN→SYN-ACK→ACK)
//   → Tidak ada HTTP, tidak ada handshake protokol
//   → Kita definisikan sendiri format framing pesan
//   → Autentikasi via pesan AUTH yang dikirim setelah koneksi terbuka
//
// Protokol framing yang digunakan (Length-Prefixed Messaging):
//   ┌──────────────────┬────────────────────────────────────┐
//   │  4 bytes header  │  N bytes payload (JSON UTF-8)      │
//   │  (UINT32 BE)     │                                    │
//   └──────────────────┴────────────────────────────────────┘
//   Header berisi panjang payload dalam byte (big-endian unsigned 32-bit int).
//   Receiver membaca 4 byte pertama, tahu berapa byte payload yang perlu dibaca.
//
// Mengapa perlu framing manual?
//   TCP adalah stream of bytes — tidak ada konsep "batas pesan".
//   Satu socket.write() bisa datang dalam beberapa potongan (fragmentation),
//   atau beberapa write bisa datang dalam satu chunk (coalescing / Nagle).
//   Length prefix memungkinkan kita merakit kembali pesan yang utuh.
//
// Security:
//   - TLS: gunakan SecureSocket.connect() di production (enkripsi transport)
//   - JWT: validasi di server saat menerima AUTH message
//   - HMAC-SHA256: signing payload untuk integritas data
//   - Reconnect tidak re-kirim data sensitif; hanya re-auth dengan token

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/constants/socket_constants.dart';
import '../../core/errors/socket_exceptions.dart'
    as app_exc;
import '../../core/utils/logger.dart';
import '../models/socket_message_model.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

/// Abstraksi datasource — untuk testability (bisa di-mock)
abstract class RawSocketDataSource {
  Future<void> connect(String token);
  Future<void> disconnect();
  Stream<ConnectionStatus> get connectionStatus;
  Stream<SocketMessageModel> get incomingMessages;
  Future<void> send(SocketMessageModel message);
  Future<SocketMessageModel> sendWithAck(
    SocketMessageModel message, {
    Duration timeout,
  });
  Future<void> dispose();
}

/// [RawSocketDataSourceImpl]
///
/// Implementasi Raw TCP Socket menggunakan dart:io Socket.
/// Menangani seluruh lifecycle koneksi, framing protokol, autentikasi,
/// reconnect, heartbeat, dan keamanan HMAC.
class RawSocketDataSourceImpl implements RawSocketDataSource {
  // ─── Config ────────────────────────────────────────────────────────────────
  final String _host;
  final int    _port;
  final String _hmacSecret;
  final bool   _useTls;  // true untuk SecureSocket di production

  // ─── State Internal ────────────────────────────────────────────────────────
  Socket?             _socket;
  StreamSubscription? _socketSub;

  // Buffer akumulasi: karena TCP bisa memecah atau menggabung data,
  // kita akumulasi semua byte yang diterima di sini.
  final _receiveBuffer = BytesBuilder(copy: false);

  // Broadcast streams
  final _statusController   = StreamController<ConnectionStatus>.broadcast();
  final _incomingController = StreamController<SocketMessageModel>.broadcast();

  // ACK registry: requestId → Completer
  // Setiap sendWithAck() mendaftarkan Completer. Ketika respons dengan
  // requestId yang sama datang, Completer di-complete.
  final Map<String, Completer<SocketMessageModel>> _pendingAcks = {};

  // Reconnect state
  int    _reconnectAttempts     = 0;
  bool   _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  String? _lastToken;

  // Heartbeat timer (client-side PING)
  Timer? _heartbeatTimer;

  RawSocketDataSourceImpl({
    required String host,
    required int    port,
    String  hmacSecret = '',
    bool    useTls     = false,
  })  : _host       = host,
        _port       = port,
        _hmacSecret = hmacSecret,
        _useTls     = useTls;

  // ─── Public API ────────────────────────────────────────────────────────────

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<SocketMessageModel> get incomingMessages => _incomingController.stream;

  /// Langkah 1: Buka koneksi TCP ke server
  /// Langkah 2: Kirim AUTH message dengan JWT token
  /// Langkah 3: Tunggu CONNECTION_ACK dari server
  @override
  Future<void> connect(String token) async {
    _lastToken            = token;
    _intentionalDisconnect = false;
    _reconnectAttempts    = 0;
    await _doConnect(token);
  }

  /// Internal connect — dipanggil saat pertama kali dan saat reconnect.
  Future<void> _doConnect(String token) async {
    _emitStatus(ConnectionStatus.connecting);

    try {
      AppLogger.info('Connecting TCP to $_host:$_port ...');

      // ── Buka TCP socket ────────────────────────────────────────────────────
      // dart:io Socket.connect() melakukan:
      //   1. Resolve hostname (DNS lookup jika bukan IP)
      //   2. Buka TCP connection (SYN → SYN-ACK → ACK)
      //   3. Return Socket object yang siap baca/tulis
      //
      // Untuk TLS/SSL (production):
      //   SecureSocket.connect(_host, _port, ...)
      //   → Setelah TCP terbuka, lakukan TLS handshake otomatis
      //   → Semua data dienkripsi dengan TLS record layer

      if (_useTls) {
        _socket = await SecureSocket.connect(
          _host,
          _port,
          timeout: SocketConstants.connectionTimeout,
          // onBadCertificate: (cert) => false, // Selalu reject invalid cert!
        );
      } else {
        _socket = await Socket.connect(
          _host,
          _port,
          timeout: SocketConstants.connectionTimeout,
        );
      }

      // Disable Nagle's algorithm: kirim data segera tanpa delay buffering.
      // Penting untuk aplikasi IoT yang membutuhkan low-latency.
      // ignore: avoid_dynamic_calls
      _socket!.setOption(SocketOption.tcpNoDelay, true);

      AppLogger.info('TCP connected to $_host:$_port');

      // ── Subscribe ke stream data masuk ────────────────────────────────────
      _socketSub = _socket!.listen(
        _onData,
        onError: _onError,
        onDone:  _onDone,
        cancelOnError: false,
      );

      // ── Kirim AUTH message ─────────────────────────────────────────────────
      // Berbeda dari WebSocket yang auth lewat URL query param,
      // di raw socket kita kirim pesan AUTH setelah koneksi terbuka.
      _emitStatus(ConnectionStatus.authenticating);

      final authMessage = SocketMessageModel.fromEntity(
        SocketMessage.auth(
          requestId: _generateRequestId(),
          token:     token,
        ),
      );

      // Tunggu CONNECTION_ACK dari server (pakai ACK pattern)
      final ack = await sendWithAck(
        authMessage,
        timeout: SocketConstants.authTimeout,
      );

      if (ack.type != MessageType.connectionAck) {
        throw app_exc.SocketAuthException(
          'Expected CONNECTION_ACK, got: ${ack.type}',
        );
      }

      AppLogger.info('Authenticated. clientId: ${ack.data?['clientId']}');
      _reconnectAttempts = 0;
      _emitStatus(ConnectionStatus.connected);

      // Mulai heartbeat timer
      _startHeartbeat();

    } on SocketException catch (e) {
      AppLogger.error('TCP connect failed: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    } on app_exc.SocketAuthException catch (e) {
      AppLogger.error('Auth failed: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      // Jangan reconnect jika auth gagal — token mungkin invalid
      rethrow;
    } catch (e) {
      AppLogger.error('Connection error: $e');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    _cancelAllPendingAcks('Disconnected by user');

    await _socketSub?.cancel();
    // Tutup socket dengan graceful shutdown: kirim TCP FIN
    await _socket?.close();
    _socket = null;

    _emitStatus(ConnectionStatus.disconnected);
    AppLogger.info('TCP socket disconnected (intentional)');
  }

  /// Kirim pesan tanpa menunggu respons.
  ///
  /// Proses pengiriman:
  ///   1. Serialize message ke JSON string
  ///   2. Encode ke bytes (UTF-8)
  ///   3. Buat 4-byte header berisi panjang payload
  ///   4. Gabungkan header + payload dan tulis ke socket
  @override
  Future<void> send(SocketMessageModel message) async {
    _ensureConnected();

    final json = message.toJson();

    // Tambahkan HMAC signature jika secret dikonfigurasi
    if (_hmacSecret.isNotEmpty) {
      json['signature'] = _signPayload(json);
    }

    // Encode JSON → bytes
    final payloadBytes = utf8.encode(jsonEncode(json));

    // Buat 4-byte length header (big-endian)
    final header = ByteData(SocketConstants.headerSize);
    header.setUint32(0, payloadBytes.length, Endian.big);

    // Gabungkan dan tulis ke TCP stream
    // socket.add() memasukkan ke send buffer kernel — tidak blocking
    _socket!.add(header.buffer.asUint8List());
    _socket!.add(payloadBytes);

    AppLogger.debug('Sent [${payloadBytes.length} bytes]: ${jsonEncode(json)}');
  }

  /// Kirim pesan dan tunggu respons dengan requestId yang sama.
  ///
  /// Ini adalah implementasi request-response di atas raw TCP yang
  /// secara native hanya mendukung unidirectional streaming.
  ///
  /// Pattern:
  ///   1. Daftarkan Completer ke _pendingAcks[requestId]
  ///   2. Kirim pesan
  ///   3. Await completer.future dengan timeout
  ///   4. _onData() mencocokkan requestId dan complete completer
  @override
  Future<SocketMessageModel> sendWithAck(
    SocketMessageModel message, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ensureConnected();

    final completer = Completer<SocketMessageModel>();
    _pendingAcks[message.requestId] = completer;

    try {
      await send(message);

      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingAcks.remove(message.requestId);
          throw app_exc.SocketTimeoutException(
            'No response for requestId: ${message.requestId}',
          );
        },
      );
    } catch (e) {
      _pendingAcks.remove(message.requestId);
      rethrow;
    }
  }

  // ─── Private: Data Processing ─────────────────────────────────────────────

  /// Dipanggil setiap kali ada data masuk dari TCP stream.
  ///
  /// KRITIS: Data bisa datang terpecah-pecah (TCP fragmentation)
  /// atau beberapa pesan bisa datang sekaligus dalam satu chunk.
  /// Kita HARUS mengakumulasi di buffer dan proses saat pesan lengkap.
  void _onData(Uint8List chunk) {
    // Tambahkan chunk ke buffer akumulasi
    _receiveBuffer.add(chunk);

    // Proses semua pesan lengkap yang ada di buffer
    _processBuffer();
  }

  /// Ekstrak dan proses semua pesan lengkap dari buffer.
  ///
  /// Format: [4-byte header][payload]
  /// Loop sampai tidak ada pesan lengkap lagi.
  void _processBuffer() {
    while (true) {
      final bufferBytes = _receiveBuffer.toBytes();

      // Perlu minimal 4 byte untuk membaca header
      if (bufferBytes.length < SocketConstants.headerSize) break;

      // Baca panjang payload dari header
      final payloadLength = ByteData.sublistView(
        bufferBytes, 0, SocketConstants.headerSize,
      ).getUint32(0, Endian.big);

      // Validasi ukuran — cegah memory exhaustion
      if (payloadLength > SocketConstants.maxPayloadBytes) {
        AppLogger.error('Payload too large: $payloadLength bytes — closing');
        _socket?.destroy();
        return;
      }

      final totalLength = SocketConstants.headerSize + payloadLength;

      // Periksa apakah seluruh payload sudah tiba
      if (bufferBytes.length < totalLength) break;

      // Ekstrak payload dari buffer
      final payloadBytes = bufferBytes.sublist(
        SocketConstants.headerSize,
        totalLength,
      );

      // Sisa buffer setelah pesan ini
      final remaining = bufferBytes.sublist(totalLength);
      _receiveBuffer.clear();
      if (remaining.isNotEmpty) _receiveBuffer.add(remaining);

      // Parse dan handle pesan
      _handleMessage(payloadBytes);
    }
  }

  /// Parse JSON dari payload dan routing ke handler yang sesuai.
  void _handleMessage(List<int> payloadBytes) {
    try {
      final jsonStr = utf8.decode(payloadBytes);
      final json    = jsonDecode(jsonStr) as Map<String, dynamic>;
      AppLogger.debug('Received: $jsonStr');

      final model = SocketMessageModel.fromJson(json);

      // ── Handle PING dari server → balas PONG ──────────────────────────────
      if (model.type == MessageType.ping) {
        _sendPong(model.requestId);
        return;
      }

      // ── Handle PONG dari server (balasan heartbeat client) ────────────────
      if (model.type == MessageType.pong) {
        AppLogger.debug('Heartbeat PONG received');
        return; // Tidak perlu diteruskan ke stream
      }

      // ── Cek ACK pending ───────────────────────────────────────────────────
      if (model.requestId.isNotEmpty &&
          _pendingAcks.containsKey(model.requestId)) {
        final completer = _pendingAcks.remove(model.requestId)!;
        if (!completer.isCompleted) {
          if (model.type == MessageType.error) {
            completer.completeError(
              app_exc.SocketServerException(
                model.errorMessage ?? 'Server error',
              ),
            );
          } else {
            completer.complete(model);
          }
        }
        return; // ACK response tidak di-broadcast
      }

      // ── Broadcast ke stream (server-push / unsolicited messages) ──────────
      if (!_incomingController.isClosed) {
        _incomingController.add(model);
      }
    } catch (e) {
      AppLogger.error('Failed to parse message: $e');
      // Jangan crash — lanjut mendengarkan
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    AppLogger.error('TCP socket error: $error');
    _emitStatus(ConnectionStatus.error);
  }

  void _onDone() {
    AppLogger.info('TCP connection closed by remote');
    _socket = null;
    _heartbeatTimer?.cancel();
    _cancelAllPendingAcks('Connection closed');

    if (!_intentionalDisconnect) {
      _emitStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  // ─── Heartbeat (sisi client) ───────────────────────────────────────────────
  //
  // Di WebSocket, heartbeat dilakukan dengan frame PING/PONG bawaan protokol.
  // Di raw socket, kita implementasikan sendiri di level aplikasi.

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      SocketConstants.clientHeartbeatInterval,
      (_) => _sendPing(),
    );
  }

  void _sendPing() {
    if (_socket == null) return;
    try {
      final pingMsg = SocketMessageModel.fromEntity(
        SocketMessage.ping(requestId: _generateRequestId()),
      );
      send(pingMsg);
      AppLogger.debug('Heartbeat PING sent');
    } catch (e) {
      AppLogger.error('Failed to send PING: $e');
    }
  }

  void _sendPong(String requestId) {
    try {
      final pongModel = SocketMessageModel(
        requestId: requestId,
        type:      MessageType.pong,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      send(pongModel);
    } catch (e) {
      AppLogger.error('Failed to send PONG: $e');
    }
  }

  // ─── Reconnect dengan Exponential Backoff ─────────────────────────────────

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= SocketConstants.maxReconnectAttempts) {
      AppLogger.error('Max reconnect attempts reached. Giving up.');
      _emitStatus(ConnectionStatus.error);
      return;
    }

    _reconnectAttempts++;
    final delay = _backoffDelay(_reconnectAttempts);

    AppLogger.info(
      'Reconnecting in ${delay}s '
      '(attempt $_reconnectAttempts/${SocketConstants.maxReconnectAttempts})',
    );
    _emitStatus(ConnectionStatus.reconnecting);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (!_intentionalDisconnect && _lastToken != null) {
        try {
          await _doConnect(_lastToken!);
        } catch (_) {
          // Error sudah di-handle di _doConnect → _scheduleReconnect dipanggil
        }
      }
    });
  }

  int _backoffDelay(int attempt) {
    final base = SocketConstants.reconnectBaseDelaySeconds;
    final max  = SocketConstants.maxReconnectDelaySeconds;
    // Exponential: base * 2^(attempt-1), capped at max
    return (base * (1 << (attempt - 1))).clamp(base, max);
  }

  // ─── Security ─────────────────────────────────────────────────────────────

  /// HMAC-SHA256 signing untuk integritas payload.
  ///
  /// Memastikan data tidak dimodifikasi di tengah jalan (man-in-the-middle).
  /// Server memverifikasi signature dengan shared secret yang sama.
  String _signPayload(Map<String, dynamic> payload) {
    final data = Map<String, dynamic>.from(payload)
      ..remove('signature'); // Hindari circular dependency

    // Sort key — server harus melakukan hal yang sama untuk konsistensi
    final sortedJson = jsonEncode(
      Map.fromEntries(
        data.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    );

    final key  = utf8.encode(_hmacSecret);
    final msg  = utf8.encode(sortedJson);
    final hmac = Hmac(sha256, key);
    return hmac.convert(msg).toString();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  void _emitStatus(ConnectionStatus status) {
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _ensureConnected() {
    if (_socket == null) {
      throw const app_exc.SocketNotConnectedException(
        'TCP socket is not connected. Call connect() first.',
      );
    }
  }

  void _cancelAllPendingAcks(String reason) {
    for (final entry in _pendingAcks.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          app_exc.SocketConnectionException(reason),
        );
      }
    }
    _pendingAcks.clear();
  }

  String _generateRequestId() {
    // Simple UUID-like ID tanpa dependency eksternal di layer ini
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = (now * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFF;
    return '${now.toRadixString(16)}-${rand.toRadixString(16)}';
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
    await _incomingController.close();
  }
}
