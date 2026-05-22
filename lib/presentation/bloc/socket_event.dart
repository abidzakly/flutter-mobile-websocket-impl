// lib/presentation/bloc/socket_event.dart

import 'package:equatable/equatable.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

abstract class SocketEvent extends Equatable {
  const SocketEvent();
  @override
  List<Object?> get props => [];
}

class SocketConnectRequested extends SocketEvent {
  final String token;
  const SocketConnectRequested(this.token);
  @override
  List<Object?> get props => [token];
}

class SocketDisconnectRequested extends SocketEvent {
  const SocketDisconnectRequested();
}

class SocketCommandSent extends SocketEvent {
  final String command;
  final Map<String, dynamic>? payload;
  const SocketCommandSent(this.command, {this.payload});
  @override
  List<Object?> get props => [command, payload];
}

class SocketConnectionStatusChanged extends SocketEvent {
  final ConnectionStatus status;
  const SocketConnectionStatusChanged(this.status);
  @override
  List<Object?> get props => [status];
}

class SocketMessageReceived extends SocketEvent {
  final SocketMessage message;
  const SocketMessageReceived(this.message);
  @override
  List<Object?> get props => [message];
}

class SocketReconnectRequested extends SocketEvent {
  const SocketReconnectRequested();
}
