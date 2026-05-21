// lib/domain/entities/socket_message.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN LAYER — Entities
// ─────────────────────────────────────────────────────────────────────────────
//
// Entity adalah objek murni domain bisnis. Tidak bergantung pada
// framework, library, atau detail implementasi apapun.
//
// SocketMessage merepresentasikan satu unit komunikasi antara
// client dan server melalui WebSocket channel.
//
// Arsitektur mengikuti Clean Architecture:
//   Presentation → Domain ← Data
//                     ↑
//                  (entity ini)

import 'package:equatable/equatable.dart';

/// Tipe pesan yang dikenali oleh sistem.
enum MessageType {
  /// Pesan dari client ke server berisi command code
  command,

  /// Respons data dari server
  dataResponse,

  /// Konfirmasi koneksi berhasil dari server
  connectionAck,

  /// Pesan error dari server
  error,

  /// Ping/pong heartbeat (internal, tidak ditampilkan ke UI)
  heartbeat,

  /// Tipe tidak dikenal — untuk forward-compatibility
  unknown,
}

/// [SocketMessage] — entity utama komunikasi WebSocket.
///
/// Immutable: semua field final, gunakan [copyWith] untuk membuat
/// instance baru dengan perubahan parsial.
class SocketMessage extends Equatable {
  /// ID unik per pesan — digunakan untuk mencocokkan request-response.
  /// Format: UUID v4 string.
  final String requestId;

  /// Tipe pesan (lihat enum [MessageType]).
  final MessageType type;

  /// Command code yang dikirim client ke server.
  /// Contoh: "001", "011", "111"
  /// Null jika ini adalah pesan respons dari server.
  final String? command;

  /// Data payload dari respons server (sudah di-decode dari JSON).
  final Map<String, dynamic>? data;

  /// Kode error jika type == MessageType.error
  final String? errorCode;

  /// Pesan error yang dapat dibaca manusia
  final String? errorMessage;

  /// Waktu pesan dibuat (epoch milliseconds)
  final int timestamp;

  const SocketMessage({
    required this.requestId,
    required this.type,
    required this.timestamp,
    this.command,
    this.data,
    this.errorCode,
    this.errorMessage,
  });

  /// Factory: buat pesan command dari client ke server
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

  /// Buat salinan dengan beberapa field diubah (immutable update pattern)
  SocketMessage copyWith({
    String? requestId,
    MessageType? type,
    String? command,
    Map<String, dynamic>? data,
    String? errorCode,
    String? errorMessage,
    int? timestamp,
  }) {
    return SocketMessage(
      requestId:    requestId    ?? this.requestId,
      type:         type         ?? this.type,
      command:      command      ?? this.command,
      data:         data         ?? this.data,
      errorCode:    errorCode    ?? this.errorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp:    timestamp    ?? this.timestamp,
    );
  }

  @override
  List<Object?> get props => [
    requestId,
    type,
    command,
    data,
    errorCode,
    errorMessage,
    timestamp,
  ];
}