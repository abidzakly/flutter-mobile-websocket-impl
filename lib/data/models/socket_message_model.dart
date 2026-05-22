// lib/data/models/socket_message_model.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — Model (DTO) — shared by both WebSocket & Raw TCP datasources
// ─────────────────────────────────────────────────────────────────────────────
//
// JSON format differences:
//
// WebSocket (toJsonWs):
//   Client → Server: { "requestId", "command", "payload"? }
//   No "type" field — server routes by message content
//
// Raw TCP (toJson):
//   Client → Server: { "type", "requestId", "timestamp", "token"?, "command"?, "payload"? }
//   "type" field required — server uses it to route since TCP has no opcodes
//
// fromJson() is shared — server always sends "type" in responses for both protocols.

import '../../domain/entities/data_item.dart';
import '../../domain/entities/socket_message.dart';

class SocketMessageModel extends SocketMessage {
  const SocketMessageModel({
    required super.requestId,
    required super.type,
    required super.timestamp,
    super.token,
    super.command,
    super.data,
    super.errorCode,
    super.errorMessage,
  });

  // ─── WebSocket format: client → server ────────────────────────────────────
  // Minimal payload — server infers type from presence of "command" field.
  // Auth is done via URL query param, so no AUTH message needed here.
  Map<String, dynamic> toJsonWs() {
    return {
      'requestId': requestId,
      if (command != null) 'command': command,
      if (data    != null) 'payload': data,
    };
  }

  // ─── Raw TCP format: client → server ──────────────────────────────────────
  // Explicit "type" required — TCP has no WebSocket opcodes for routing.
  Map<String, dynamic> toJson() {
    return {
      'type':      _typeToString(type),
      'requestId': requestId,
      'timestamp': timestamp,
      if (token   != null) 'token':   token,
      if (command != null) 'command': command,
      if (data    != null) 'payload': data,
    };
  }

  // ─── Shared: server → client (both protocols respond with "type") ──────────
  factory SocketMessageModel.fromJson(Map<String, dynamic> json) {
    return SocketMessageModel(
      requestId:    json['requestId']  as String? ?? '',
      type:         _parseType(json['type'] as String? ?? ''),
      token:        json['token']      as String?,
      command:      json['command']    as String?,
      data:         json['data']       as Map<String, dynamic>?,
      errorCode:    json['code']       as String?,
      errorMessage: json['message']    as String?,
      timestamp:    json['timestamp']  as int?
                    ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory SocketMessageModel.fromEntity(SocketMessage entity) {
    return SocketMessageModel(
      requestId:    entity.requestId,
      type:         entity.type,
      token:        entity.token,
      command:      entity.command,
      data:         entity.data,
      errorCode:    entity.errorCode,
      errorMessage: entity.errorMessage,
      timestamp:    entity.timestamp,
    );
  }

  static String _typeToString(MessageType type) {
    switch (type) {
      case MessageType.auth:          return 'AUTH';
      case MessageType.command:       return 'COMMAND';
      case MessageType.dataResponse:  return 'DATA_RESPONSE';
      case MessageType.connectionAck: return 'CONNECTION_ACK';
      case MessageType.error:         return 'ERROR';
      case MessageType.ping:          return 'PING';
      case MessageType.pong:          return 'PONG';
      case MessageType.unknown:       return 'UNKNOWN';
    }
  }

  static MessageType _parseType(String typeStr) {
    switch (typeStr) {
      case 'AUTH':           return MessageType.auth;
      case 'COMMAND':        return MessageType.command;
      case 'DATA_RESPONSE':  return MessageType.dataResponse;
      case 'CONNECTION_ACK': return MessageType.connectionAck;
      case 'ERROR':          return MessageType.error;
      case 'PING':           return MessageType.ping;
      case 'PONG':           return MessageType.pong;
      default:               return MessageType.unknown;
    }
  }
}

// ─── DataItemModel ────────────────────────────────────────────────────────────
class DataItemModel extends DataItem {
  const DataItemModel({
    required super.id,
    required super.name,
    required super.value,
    required super.category,
    super.description,
  });

  factory DataItemModel.fromJson(Map<String, dynamic> json) {
    return DataItemModel(
      id:          json['id']          as String,
      name:        json['name']        as String,
      value:       json['value']       as int,
      category:    json['category']    as String,
      description: json['description'] as String?,
    );
  }

  static List<DataItemModel> listFromJson(List<dynamic> jsonList) {
    return jsonList
        .map((item) => DataItemModel.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
