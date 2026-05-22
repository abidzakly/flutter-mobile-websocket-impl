// lib/domain/repositories/socket_repository.dart

import '../entities/socket_message.dart';

abstract class SocketRepository {
  Future<void> connect(String token);
  Future<void> disconnect();
  Stream<ConnectionStatus> get connectionStatus;
  Future<void> send(SocketMessage message);
  Future<SocketMessage> sendWithAck(
    SocketMessage message, {
    Duration timeout,
  });
  Stream<SocketMessage> get incomingMessages;
}

enum ConnectionStatus {
  idle,
  connecting,
  authenticating, // TCP only: after TCP open, before AUTH_ACK
  connected,
  disconnected,
  reconnecting,
  error,
}
