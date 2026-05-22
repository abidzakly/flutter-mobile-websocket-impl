// lib/domain/usecases/socket_usecases.dart

import 'package:uuid/uuid.dart';
import '../entities/socket_message.dart';
import '../repositories/socket_repository.dart';

const _uuid = Uuid();

class ConnectSocketUseCase {
  final SocketRepository _repository;
  const ConnectSocketUseCase(this._repository);
  Future<void> call(String token) => _repository.connect(token);
}

class DisconnectSocketUseCase {
  final SocketRepository _repository;
  const DisconnectSocketUseCase(this._repository);
  Future<void> call() => _repository.disconnect();
}

/// Kirim command dan tunggu ACK dari server.
/// Acceptance criteria: "Pastikan data yang terkirim sudah terkirim dari server"
class SendCommandUseCase {
  final SocketRepository _repository;
  const SendCommandUseCase(this._repository);

  Future<SocketMessage> call(
    String command, {
    Map<String, dynamic>? payload,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final message = SocketMessage.command(
      requestId: _uuid.v4(),
      command: command,
      payload: payload,
    );
    return _repository.sendWithAck(message, timeout: timeout);
  }
}

class WatchConnectionStatusUseCase {
  final SocketRepository _repository;
  const WatchConnectionStatusUseCase(this._repository);
  Stream<ConnectionStatus> call() => _repository.connectionStatus;
}

class WatchIncomingMessagesUseCase {
  final SocketRepository _repository;
  const WatchIncomingMessagesUseCase(this._repository);
  Stream<SocketMessage> call() => _repository.incomingMessages;
}
