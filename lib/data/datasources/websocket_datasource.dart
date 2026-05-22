// lib/data/datasources/websocket_datasource.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — WebSocket Data Source
// ─────────────────────────────────────────────────────────────────────────────
//
// Menggunakan dart:io WebSocket — wrapper di atas TCP yang menangani
// WebSocket protocol (RFC 6455) secara otomatis:
//   - HTTP Upgrade handshake (GET + "Upgrade: websocket" header)
//   - Frame encoding/decoding (text, binary, ping, pong, close frames)
//   - Client-to-server masking (sesuai RFC 6455 spec)
//
// Autentikasi: JWT dikirim via query parameter saat HTTP Upgrade:
//   ws://host:8080?token=<JWT>
//
// Berbeda dari RawSocketDataSource:
//   - Tidak ada manual framing (WebSocket protocol menangani sendiri)
//   - Tidak ada AUTH message — auth di URL handshake
//   - PING/PONG ditangani di level WebSocket frame, bukan aplikasi
//   - Koneksi langsung "ready" setelah connect() — tidak ada auth step

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/constants/socket_constants.dart';
import '../../core/errors/socket_exceptions.dart' as app_exc;
import '../../core/utils/logger.dart';
import '../models/socket_message_model.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

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
  Future<void> dispose();
}

class WebSocketDataSourceImpl implements WebSocketDataSource {
  final String _baseUrl;
  final String _hmacSecret;

  WebSocket? _socket;
  StreamSubscription? _socketSub;

  final _statusController   = StreamController<ConnectionStatus>.broadcast();
  final _incomingController = StreamController<SocketMessageModel>.broadcast();
  final Map<String, Completer<SocketMessageModel>> _pendingAcks = {};

  int    _reconnectAttempts     = 0;
  bool   _intentionalDisconnect = false;
  Timer? _reconnectTimer;
  String? _lastToken;

  WebSocketDataSourceImpl({
    required String baseUrl,
    String hmacSecret = '',
  })  : _baseUrl     = baseUrl,
        _hmacSecret  = hmacSecret;

  @override
  Stream<ConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  Stream<SocketMessageModel> get incomingMessages => _incomingController.stream;

  @override
  Future<void> connect(String token) async {
    _lastToken             = token;
    _intentionalDisconnect = false;
    _reconnectAttempts     = 0;
    await _doConnect(token);
  }

  Future<void> _doConnect(String token) async {
    _emitStatus(ConnectionStatus.connecting);

    try {
      // JWT dikirim via query parameter pada HTTP Upgrade request.
      // Browser native WebSocket tidak mendukung custom header,
      // sehingga query param adalah cara standar untuk WS auth.
      final uri = Uri.parse('$_baseUrl?token=${Uri.encodeComponent(token)}');
      AppLogger.info('WS connecting to: ${uri.host}:${uri.port}');

      // dart:io WebSocket.connect():
      //   1. Buka TCP socket ke server
      //   2. Kirim HTTP GET + "Upgrade: websocket" header
      //   3. Tunggu "101 Switching Protocols" dari server
      //   4. Komunikasi menjadi full-duplex WebSocket frames
      _socket = await WebSocket.connect(
        uri.toString(),
        headers: {
          'X-Client-Version': SocketConstants.clientVersion,
          'ngrok-skip-browser-warning': 'true',
        },
      ).timeout(
        SocketConstants.connectionTimeout,
        onTimeout: () => throw const app_exc.SocketConnectionException(
          'WS connection timed out',
        ),
      );

      AppLogger.info('WS connected');
      _reconnectAttempts = 0;
      _emitStatus(ConnectionStatus.connected);

      _socketSub = _socket!.listen(
        _onMessage,
        onError: _onError,
        onDone:  _onDone,
        cancelOnError: false,
      );
    } on SocketException catch (e) {
      AppLogger.error('WS socket error: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    } on WebSocketException catch (e) {
      AppLogger.error('WS handshake failed: ${e.message}');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    } catch (e) {
      AppLogger.error('WS unexpected error: $e');
      _emitStatus(ConnectionStatus.error);
      _scheduleReconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _cancelAllPendingAcks('Disconnected by user');
    await _socketSub?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure, 'Client disconnected');
    _socket = null;
    _emitStatus(ConnectionStatus.disconnected);
    AppLogger.info('WS disconnected (intentional)');
  }

  @override
  Future<void> send(SocketMessageModel message) async {
    _ensureConnected();
    final json = message.toJsonWs(); // WS format: no "type" prefix needed
    if (_hmacSecret.isNotEmpty) json['signature'] = _signPayload(json);
    final jsonString = jsonEncode(json);
    AppLogger.debug('WS sending: $jsonString');
    _socket!.add(jsonString);
  }

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
            'No ACK for requestId: ${message.requestId}',
          );
        },
      );
    } catch (e) {
      _pendingAcks.remove(message.requestId);
      rethrow;
    }
  }

  void _onMessage(dynamic rawData) {
    try {
      final Map<String, dynamic> json = jsonDecode(rawData as String);
      AppLogger.debug('WS received: $rawData');
      final model = SocketMessageModel.fromJson(json);

      if (model.requestId.isNotEmpty &&
          _pendingAcks.containsKey(model.requestId)) {
        final completer = _pendingAcks.remove(model.requestId)!;
        if (!completer.isCompleted) {
          if (model.type == MessageType.error) {
            completer.completeError(
              app_exc.SocketServerException(model.errorMessage ?? 'Server error'),
            );
          } else {
            completer.complete(model);
          }
        }
        return;
      }

      if (!_incomingController.isClosed) {
        _incomingController.add(model);
      }
    } catch (e) {
      AppLogger.error('WS parse error: $e');
    }
  }

  void _onError(Object error, StackTrace _) {
    AppLogger.error('WS error: $error');
    _emitStatus(ConnectionStatus.error);
  }

  void _onDone() {
    AppLogger.info('WS connection closed');
    _socket = null;
    _cancelAllPendingAcks('Connection closed');
    if (!_intentionalDisconnect) {
      _emitStatus(ConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect) return;
    if (_reconnectAttempts >= SocketConstants.maxReconnectAttempts) {
      AppLogger.error('WS max reconnect attempts reached');
      _emitStatus(ConnectionStatus.error);
      return;
    }
    _reconnectAttempts++;
    final delay = _backoffDelay(_reconnectAttempts);
    AppLogger.info('WS reconnecting in ${delay}s (attempt $_reconnectAttempts)');
    _emitStatus(ConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (!_intentionalDisconnect && _lastToken != null) {
        try {
          await _doConnect(_lastToken!);
        } catch (_) {}
      }
    });
  }

  int _backoffDelay(int attempt) {
    final base = SocketConstants.reconnectBaseDelaySeconds;
    final max  = SocketConstants.maxReconnectDelaySeconds;
    return (base * (1 << (attempt - 1))).clamp(base, max);
  }

  String _signPayload(Map<String, dynamic> payload) {
    final data = Map<String, dynamic>.from(payload)..remove('signature');
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

  void _emitStatus(ConnectionStatus status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _ensureConnected() {
    if (_socket == null || _socket!.readyState != WebSocket.open) {
      throw const app_exc.SocketNotConnectedException(
        'WebSocket is not connected. Call connect() first.',
      );
    }
  }

  void _cancelAllPendingAcks(String reason) {
    for (final e in _pendingAcks.entries) {
      if (!e.value.isCompleted) {
        e.value.completeError(app_exc.SocketConnectionException(reason));
      }
    }
    _pendingAcks.clear();
  }

  @override
  Future<void> dispose() async {
    await disconnect();
    await _statusController.close();
    await _incomingController.close();
  }
}
