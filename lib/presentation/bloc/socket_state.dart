// lib/presentation/bloc/socket_state.dart

import 'package:equatable/equatable.dart';
import '../../domain/entities/data_item.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';

enum CommandStatus { idle, sending, success, failure }

class SocketState extends Equatable {
  final ConnectionStatus connectionStatus;
  final CommandStatus    commandStatus;
  final List<DataItem>   receivedItems;
  final List<SocketMessage> messageHistory;
  final String?          errorMessage;
  final String?          lastSentCommand;
  final int              reconnectAttempts;

  const SocketState({
    required this.connectionStatus,
    required this.commandStatus,
    required this.receivedItems,
    required this.messageHistory,
    this.errorMessage,
    this.lastSentCommand,
    this.reconnectAttempts = 0,
  });

  factory SocketState.initial() => const SocketState(
    connectionStatus: ConnectionStatus.idle,
    commandStatus:    CommandStatus.idle,
    receivedItems:    [],
    messageHistory:   [],
  );

  bool get isConnected     => connectionStatus == ConnectionStatus.connected;
  bool get isConnecting    => connectionStatus == ConnectionStatus.connecting ||
                              connectionStatus == ConnectionStatus.authenticating;
  bool get isReconnecting  => connectionStatus == ConnectionStatus.reconnecting;
  bool get canSendCommand  => isConnected && commandStatus != CommandStatus.sending;

  SocketState copyWith({
    ConnectionStatus? connectionStatus,
    CommandStatus?    commandStatus,
    List<DataItem>?   receivedItems,
    List<SocketMessage>? messageHistory,
    String?           errorMessage,
    String?           lastSentCommand,
    int?              reconnectAttempts,
    bool              clearError = false,
  }) {
    return SocketState(
      connectionStatus:  connectionStatus  ?? this.connectionStatus,
      commandStatus:     commandStatus     ?? this.commandStatus,
      receivedItems:     receivedItems     ?? this.receivedItems,
      messageHistory:    messageHistory    ?? this.messageHistory,
      errorMessage:      clearError ? null : (errorMessage ?? this.errorMessage),
      lastSentCommand:   lastSentCommand   ?? this.lastSentCommand,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
    );
  }

  @override
  List<Object?> get props => [
    connectionStatus, commandStatus, receivedItems,
    messageHistory, errorMessage, lastSentCommand, reconnectAttempts,
  ];
}
