// lib/domain/entities/socket_message.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN LAYER — Entities
// ─────────────────────────────────────────────────────────────────────────────
//
// Perbedaan dari versi WebSocket:
// - Tambah MessageType.auth (client kirim token untuk autentikasi)
// - Tambah MessageType.ping / pong (heartbeat di level aplikasi, bukan protokol)
// - Tidak ada HTTP Upgrade — autentikasi dilakukan via pesan AUTH setelah connect

import 'package:equatable/equatable.dart';

enum MessageType {
  /// Client → Server: autentikasi dengan JWT token
  auth,

  /// Client → Server: command code untuk meminta data
  command,

  /// Server → Client: respons data sesuai command
  dataResponse,

  /// Server → Client: konfirmasi auth dan koneksi berhasil
  connectionAck,

  /// Error dari server atau client
  error,

  /// Heartbeat ping (client atau server bisa mengirim)
  ping,

  /// Heartbeat pong (balasan ping)
  pong,

  /// Tipe tidak dikenal — forward-compatibility
  unknown,
}

/// [SocketMessage] — entity utama komunikasi Raw TCP Socket.
///
/// Immutable. Gunakan [copyWith] atau factory constructors untuk
/// membuat instance baru dengan perubahan parsial.
class SocketMessage extends Equatable {
  final String requestId;
  final MessageType type;

  /// JWT token — diisi hanya pada MessageType.auth
  final String? token;

  /// Command code — diisi pada MessageType.command (misal: "001", "011")
  final String? command;

  /// Data payload dari respons server
  final Map<String, dynamic>? data;

  final String? errorCode;
  final String? errorMessage;
  final int timestamp;

  const SocketMessage({
    required this.requestId,
    required this.type,
    required this.timestamp,
    this.token,
    this.command,
    this.data,
    this.errorCode,
    this.errorMessage,
  });

  /// Buat pesan AUTH untuk dikirim pertama kali setelah TCP connect
  factory SocketMessage.auth({
    required String requestId,
    required String token,
  }) {
    return SocketMessage(
      requestId: requestId,
      type: MessageType.auth,
      token: token,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Buat pesan COMMAND
  factory SocketMessage.command({
    required String requestId,
    required String command,
    Map<String, dynamic>? payload,
  }) {
    return SocketMessage(
      requestId: requestId,
      type: MessageType.command,
      command: command,
      data: payload,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Buat pesan PING (heartbeat dari client)
  factory SocketMessage.ping({required String requestId}) {
    return SocketMessage(
      requestId: requestId,
      type: MessageType.ping,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  SocketMessage copyWith({
    String? requestId,
    MessageType? type,
    String? token,
    String? command,
    Map<String, dynamic>? data,
    String? errorCode,
    String? errorMessage,
    int? timestamp,
  }) {
    return SocketMessage(
      requestId:    requestId    ?? this.requestId,
      type:         type         ?? this.type,
      token:        token        ?? this.token,
      command:      command      ?? this.command,
      data:         data         ?? this.data,
      errorCode:    errorCode    ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp:    timestamp    ?? this.timestamp,
    );
  }

  @override
  List<Object?> get props => [
    requestId, type, token, command, data, errorCode, errorMessage, timestamp,
  ];
}
