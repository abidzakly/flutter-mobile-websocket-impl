// lib/data/repositories/socket_repository_impl.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DATA LAYER — Repository Implementation
// ─────────────────────────────────────────────────────────────────────────────
//
// Implementasi konkret dari interface SocketRepository (domain layer).
// Menjadi jembatan antara domain dan datasource.
//
// Tugas utama:
//   1. Delegasi operasi ke datasource
//   2. Konversi model ↔ entity (mapping layer)
//   3. Error handling / transformasi exception

import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';
import '../datasources/websocket_datasource.dart';
import '../models/socket_message_model.dart';

class SocketRepositoryImpl implements SocketRepository {
  final WebSocketDataSource _dataSource;

  const SocketRepositoryImpl(this._dataSource);

  @override
  Future<void> connect(String token) => _dataSource.connect(token);

  @override
  Future<void> disconnect() => _dataSource.disconnect();

  @override
  Stream<ConnectionStatus> get connectionStatus => _dataSource.connectionStatus;

  /// Stream pesan masuk — konversi SocketMessageModel ke SocketMessage (entity)
  @override
  Stream<SocketMessage> get incomingMessages => _dataSource.incomingMessages;

  @override
  Future<void> send(SocketMessage message) {
    final model = SocketMessageModel.fromEntity(message);
    return _dataSource.send(model);
  }

  @override
  Future<SocketMessage> sendWithAck(
      SocketMessage message, {
        Duration timeout = const Duration(seconds: 10),
      }) async {
    final model = SocketMessageModel.fromEntity(message);
    // Kembalikan langsung — SocketMessageModel extends SocketMessage
    return _dataSource.sendWithAck(model, timeout: timeout);
  }
}