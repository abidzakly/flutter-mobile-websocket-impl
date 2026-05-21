// lib/domain/usecases/socket_usecases.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN LAYER — Use Cases
// ─────────────────────────────────────────────────────────────────────────────
//
// Use Case mengenkapsulasi satu unit business logic yang spesifik.
// Menerima repository melalui constructor injection.
//
// Manfaat memisahkan use case:
//   1. Single Responsibility — setiap class hanya satu tujuan
//   2. Testable secara individual
//   3. BLoC hanya bergantung pada use case, bukan repository langsung

import 'package:uuid/uuid.dart';
import '../../domain/entities/socket_message.dart';
import '../repositories/socket_repository.dart';

const _uuid = Uuid();

/// [ConnectSocketUseCase]
/// Menghubungkan client ke WebSocket server dengan JWT token.
class ConnectSocketUseCase {
  final SocketRepository _repository;
  const ConnectSocketUseCase(this._repository);

  Future<void> call(String token) => _repository.connect(token);
}

/// [DisconnectSocketUseCase]
/// Memutus koneksi WebSocket secara graceful.
class DisconnectSocketUseCase {
  final SocketRepository _repository;
  const DisconnectSocketUseCase(this._repository);

  Future<void> call() => _repository.disconnect();
}

/// [SendCommandUseCase]
/// Mengirim command ke server dan menunggu konfirmasi respons (ACK pattern).
///
/// Ini memenuhi acceptance criteria:
/// "Pastikan data yang terkirim sudah terkirim dari server ataupun client"
///
/// [command]  — kode command, misal "001", "011", "111"
/// [payload]  — data tambahan yang dikirim bersama command (opsional)
class SendCommandUseCase {
  final SocketRepository _repository;
  const SendCommandUseCase(this._repository);

  /// Kirim command dan tunggu respons dari server.
  ///
  /// Setiap request mendapat requestId unik (UUID v4) sehingga
  /// respons dapat dicocokkan dengan request-nya.
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

    // sendWithAck menunggu hingga server mengirim respons dengan requestId sama
    return _repository.sendWithAck(message, timeout: timeout);
  }
}

/// [WatchConnectionStatusUseCase]
/// Memberikan stream status koneksi — digunakan BLoC untuk reactive update.
class WatchConnectionStatusUseCase {
  final SocketRepository _repository;
  const WatchConnectionStatusUseCase(this._repository);

  Stream<ConnectionStatus> call() => _repository.connectionStatus;
}

/// [WatchIncomingMessagesUseCase]
/// Mendengarkan semua pesan masuk dari server secara real-time.
/// BLoC subscribe ke stream ini untuk update data lokal.
class WatchIncomingMessagesUseCase {
  final SocketRepository _repository;
  const WatchIncomingMessagesUseCase(this._repository);

  Stream<SocketMessage> call() => _repository.incomingMessages;
}