// lib/presentation/bloc/socket_event.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION LAYER — BLoC Events
// ─────────────────────────────────────────────────────────────────────────────
//
// Event adalah "input" ke BLoC — merepresentasikan aksi pengguna
// atau kejadian eksternal (koneksi berubah, pesan masuk, dll).
//
// Semua event immutable dan menggunakan Equatable untuk perbandingan.
//
// Hierarki event:
//   SocketEvent (abstract)
//     ├── SocketConnectRequested       → User menekan tombol Connect
//     ├── SocketDisconnectRequested    → User menekan tombol Disconnect
//     ├── SocketCommandSent            → User memilih command dan kirim
//     ├── SocketConnectionStatusChanged → Status koneksi berubah (dari stream)
//     ├── SocketMessageReceived        → Pesan push masuk dari server
//     └── SocketReconnectRequested     → User menekan "Retry" saat error

import 'package:equatable/equatable.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

/// Base class untuk semua event
abstract class SocketEvent extends Equatable {
  const SocketEvent();
}

/// User meminta koneksi ke server.
/// [token] — JWT authentication token
class SocketConnectRequested extends SocketEvent {
  final String token;
  const SocketConnectRequested({required this.token});

  @override
  List<Object?> get props => [token];
}

/// User meminta disconnect dari server.
class SocketDisconnectRequested extends SocketEvent {
  const SocketDisconnectRequested();

  @override
  List<Object?> get props => [];
}

/// User mengirim command ke server.
///
/// [command] — kode command: "001", "011", "111"
/// [payload] — data tambahan (opsional)
class SocketCommandSent extends SocketEvent {
  final String command;
  final Map<String, dynamic>? payload;

  const SocketCommandSent({
    required this.command,
    this.payload,
  });

  @override
  List<Object?> get props => [command, payload];
}

/// Status koneksi berubah (dari stream di repository).
/// Event internal — tidak dipicu langsung oleh user.
class SocketConnectionStatusChanged extends SocketEvent {
  final ConnectionStatus status;
  const SocketConnectionStatusChanged(this.status);

  @override
  List<Object?> get props => [status];
}

/// Pesan server-push masuk (broadcast dari server).
/// Event internal — dipicu oleh stream incomingMessages.
class SocketMessageReceived extends SocketEvent {
  final SocketMessage message;
  const SocketMessageReceived(this.message);

  @override
  List<Object?> get props => [message];
}

/// User menekan retry setelah error.
class SocketReconnectRequested extends SocketEvent {
  const SocketReconnectRequested();

  @override
  List<Object?> get props => [];
}