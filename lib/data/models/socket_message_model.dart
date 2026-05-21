// lib/data/models/socket_message_model.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — Model (DTO)
// ─────────────────────────────────────────────────────────────────────────────
//
// Model adalah Data Transfer Object (DTO) — bertanggung jawab untuk
// serialisasi/deserialisasi JSON dari/ke network.
//
// Model extends Entity sehingga dapat langsung digunakan di domain.
// Alternatif: pisahkan sepenuhnya dan gunakan mapper — tergantung preferensi tim.

import '../../domain/entities/socket_message.dart';
import '../../domain/entities/data_item.dart';

/// [SocketMessageModel] — DTO untuk parsing JSON dari/ke WebSocket.
///
/// Semua JSON dari/ke server harus melalui class ini.
class SocketMessageModel extends SocketMessage {
  const SocketMessageModel({
    required super.requestId,
    required super.type,
    required super.timestamp,
    super.command,
    super.data,
    super.errorCode,
    super.errorMessage,
  });

  // ─── Serialisasi: Entity → JSON (untuk dikirim ke server) ──────────────────

  /// Konversi ke Map yang siap di-encode menjadi JSON string.
  ///
  /// Format yang dikirim ke server:
  /// ```json
  /// {
  ///   "requestId": "550e8400-...",
  ///   "command":   "001",
  ///   "payload":   {}
  /// }
  /// ```
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'command':   command,
      // "payload" diisi dari field "data" pada entity command
      if (data != null) 'payload': data,
    };
  }

  // ─── Deserialisasi: JSON → Model (untuk diterima dari server) ──────────────

  /// Parse JSON dari server menjadi [SocketMessageModel].
  ///
  /// Format yang diterima dari server:
  /// ```json
  /// {
  ///   "type":      "DATA_RESPONSE",
  ///   "requestId": "550e8400-...",
  ///   "command":   "001",
  ///   "data":      { "items": [...], "matched": [...] },
  ///   "timestamp": 1234567890
  /// }
  /// ```
  factory SocketMessageModel.fromJson(Map<String, dynamic> json) {
    return SocketMessageModel(
      requestId:    json['requestId'] as String? ?? '',
      type:         _parseMessageType(json['type'] as String? ?? ''),
      command:      json['command']      as String?,
      data:         json['data']         as Map<String, dynamic>?,
      errorCode:    json['code']         as String?,
      errorMessage: json['message']      as String?,
      timestamp:    json['timestamp']    as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Konversi dari domain entity [SocketMessage] ke model.
  factory SocketMessageModel.fromEntity(SocketMessage entity) {
    return SocketMessageModel(
      requestId:    entity.requestId,
      type:         entity.type,
      command:      entity.command,
      data:         entity.data,
      errorCode:    entity.errorCode,
      errorMessage: entity.errorMessage,
      timestamp:    entity.timestamp,
    );
  }

  // ─── Helper: parse string type dari server ke enum ─────────────────────────
  static MessageType _parseMessageType(String typeStr) {
    switch (typeStr) {
      case 'DATA_RESPONSE':    return MessageType.dataResponse;
      case 'CONNECTION_ACK':   return MessageType.connectionAck;
      case 'ERROR':            return MessageType.error;
      default:                 return MessageType.unknown;
    }
  }
}

/// [DataItemModel] — DTO untuk item data dalam respons server.
class DataItemModel extends DataItem {
  const DataItemModel({
    required super.id,
    required super.name,
    required super.value,
    required super.category,
  });

  factory DataItemModel.fromJson(Map<String, dynamic> json) {
    return DataItemModel(
      id:       json['id']       as String,
      name:     json['name']     as String,
      value:    json['value']    as int,
      category: json['category'] as String,
    );
  }

  /// Parse list dari JSON array
  static List<DataItemModel> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .map((item) => DataItemModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}