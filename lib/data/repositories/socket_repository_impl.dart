// lib/data/repositories/socket_repository_impl.dart
//
// Two concrete implementations of SocketRepository:
//   - WebSocketRepositoryImpl  → delegates to WebSocketDataSourceImpl
//   - TcpSocketRepositoryImpl  → delegates to RawSocketDataSourceImpl
//
// BLoC and use cases only depend on SocketRepository (the interface),
// so they work identically regardless of which impl is injected.

import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';
import '../datasources/websocket_datasource.dart';
import '../datasources/raw_socket_datasource.dart';
import '../models/socket_message_model.dart';

// ─── WebSocket Repository ─────────────────────────────────────────────────────
class WebSocketRepositoryImpl implements SocketRepository {
  final WebSocketDataSource _dataSource;
  const WebSocketRepositoryImpl(this._dataSource);

  @override Future<void> connect(String token) => _dataSource.connect(token);
  @override Future<void> disconnect()           => _dataSource.disconnect();
  @override Stream<ConnectionStatus> get connectionStatus => _dataSource.connectionStatus;
  @override Stream<SocketMessage>    get incomingMessages => _dataSource.incomingMessages;

  @override
  Future<void> send(SocketMessage message) =>
      _dataSource.send(SocketMessageModel.fromEntity(message));

  @override
  Future<SocketMessage> sendWithAck(
    SocketMessage message, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _dataSource.sendWithAck(
        SocketMessageModel.fromEntity(message),
        timeout: timeout,
      );
}

// ─── Raw TCP Socket Repository ────────────────────────────────────────────────
class TcpSocketRepositoryImpl implements SocketRepository {
  final RawSocketDataSource _dataSource;
  const TcpSocketRepositoryImpl(this._dataSource);

  @override Future<void> connect(String token) => _dataSource.connect(token);
  @override Future<void> disconnect()           => _dataSource.disconnect();
  @override Stream<ConnectionStatus> get connectionStatus => _dataSource.connectionStatus;
  @override Stream<SocketMessage>    get incomingMessages => _dataSource.incomingMessages;

  @override
  Future<void> send(SocketMessage message) =>
      _dataSource.send(SocketMessageModel.fromEntity(message));

  @override
  Future<SocketMessage> sendWithAck(
    SocketMessage message, {
    Duration timeout = const Duration(seconds: 10),
  }) =>
      _dataSource.sendWithAck(
        SocketMessageModel.fromEntity(message),
        timeout: timeout,
      );
}
