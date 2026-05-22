// lib/presentation/bloc/socket_bloc.dart
//
// BLoC yang identik dengan versi WebSocket dalam hal struktur,
// karena perubahan ke raw socket sepenuhnya tersembunyi di layer Data.
// Ini adalah kekuatan Clean Architecture — perubahan implementasi
// tidak merembet ke layer Presentation.

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/socket_exceptions.dart' as app_exc;
import '../../core/utils/logger.dart';
import '../../data/models/socket_message_model.dart';
import '../../domain/entities/data_item.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';
import '../../domain/usecases/socket_usecases.dart';
import 'socket_event.dart';
import 'socket_state.dart';

class SocketBloc extends Bloc<SocketEvent, SocketState> {
  final ConnectSocketUseCase         _connectUseCase;
  final DisconnectSocketUseCase      _disconnectUseCase;
  final SendCommandUseCase           _sendCommandUseCase;
  final WatchConnectionStatusUseCase _watchStatusUseCase;
  final WatchIncomingMessagesUseCase _watchMessagesUseCase;

  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<SocketMessage>?   _messagesSub;

  SocketBloc({
    required ConnectSocketUseCase         connectUseCase,
    required DisconnectSocketUseCase      disconnectUseCase,
    required SendCommandUseCase           sendCommandUseCase,
    required WatchConnectionStatusUseCase watchStatusUseCase,
    required WatchIncomingMessagesUseCase watchMessagesUseCase,
  })  : _connectUseCase      = connectUseCase,
        _disconnectUseCase   = disconnectUseCase,
        _sendCommandUseCase  = sendCommandUseCase,
        _watchStatusUseCase  = watchStatusUseCase,
        _watchMessagesUseCase = watchMessagesUseCase,
        super(SocketState.initial()) {

    on<SocketConnectRequested>        (_onConnectRequested);
    on<SocketDisconnectRequested>     (_onDisconnectRequested);
    on<SocketCommandSent>             (_onCommandSent);
    on<SocketConnectionStatusChanged> (_onConnectionStatusChanged);
    on<SocketMessageReceived>         (_onMessageReceived);
    on<SocketReconnectRequested>      (_onReconnectRequested);

    _startListening();
  }

  void _startListening() {
    _statusSub = _watchStatusUseCase().listen(
      (status) => add(SocketConnectionStatusChanged(status)),
      onError:   (err) => AppLogger.error('Status stream error: $err'),
    );

    _messagesSub = _watchMessagesUseCase().listen(
      (message) => add(SocketMessageReceived(message)),
      onError:    (err) => AppLogger.error('Messages stream error: $err'),
    );
  }

  Future<void> _onConnectRequested(
    SocketConnectRequested event,
    Emitter<SocketState> emit,
  ) async {
    AppLogger.info('BLoC: connect requested');
    try {
      emit(state.copyWith(clearError: true));
      await _connectUseCase(event.token);
    } catch (e) {
      emit(state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage:     _friendlyError(e),
      ));
    }
  }

  Future<void> _onDisconnectRequested(
    SocketDisconnectRequested event,
    Emitter<SocketState> emit,
  ) async {
    AppLogger.info('BLoC: disconnect requested');
    await _disconnectUseCase();
  }

  Future<void> _onCommandSent(
    SocketCommandSent event,
    Emitter<SocketState> emit,
  ) async {
    if (!state.canSendCommand) {
      AppLogger.warn('Command rejected: not connected or already sending');
      return;
    }

    AppLogger.info('BLoC: sending command ${event.command}');

    emit(state.copyWith(
      commandStatus:   CommandStatus.sending,
      lastSentCommand: event.command,
      clearError:      true,
    ));

    try {
      final response = await _sendCommandUseCase(
        event.command,
        payload: event.payload,
      );

      // Update data lokal dari respons server
      // Acceptance criteria: "Update data lokal dari client setelah menerima data dari server"
      final newItems      = _parseItemsFromResponse(response);
      final updatedHistory = [...state.messageHistory, response];

      emit(state.copyWith(
        commandStatus:  CommandStatus.success,
        receivedItems:  newItems,
        messageHistory: updatedHistory,
        clearError:     true,
      ));

      AppLogger.info(
        'Command ${event.command} → received ${newItems.length} items',
      );

    } on app_exc.SocketTimeoutException catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage:  'Request timed out. Please try again.',
      ));
      AppLogger.error('Command timeout: ${e.message}');

    } on app_exc.SocketServerException catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage:  'Server error: ${e.message}',
      ));
      AppLogger.error('Server error: ${e.message}');

    } catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage:  _friendlyError(e),
      ));
      AppLogger.error('Command failed: $e');
    }
  }

  void _onConnectionStatusChanged(
    SocketConnectionStatusChanged event,
    Emitter<SocketState> emit,
  ) {
    AppLogger.info('BLoC: status → ${event.status.name}');

    final reconnectAttempts = event.status == ConnectionStatus.reconnecting
        ? state.reconnectAttempts + 1
        : state.reconnectAttempts;

    emit(state.copyWith(
      connectionStatus:  event.status,
      reconnectAttempts: reconnectAttempts,
      clearError:        event.status == ConnectionStatus.connected,
    ));
  }

  void _onMessageReceived(
    SocketMessageReceived event,
    Emitter<SocketState> emit,
  ) {
    final message        = event.message;
    final updatedHistory = [...state.messageHistory, message];

    if (message.type == MessageType.dataResponse) {
      final newItems = _parseItemsFromResponse(message);
      emit(state.copyWith(
        receivedItems:  newItems,
        messageHistory: updatedHistory,
      ));
    } else {
      emit(state.copyWith(messageHistory: updatedHistory));
    }
  }

  Future<void> _onReconnectRequested(
    SocketReconnectRequested event,
    Emitter<SocketState> emit,
  ) async {
    if (state.isReconnecting) return;
    emit(state.copyWith(reconnectAttempts: 0, clearError: true));
    AppLogger.info('BLoC: manual reconnect requested');
    // Re-trigger connect dengan token terakhir jika ada
  }

  List<DataItem> _parseItemsFromResponse(SocketMessage response) {
    try {
      final items = response.data?['items'] as List<dynamic>?;
      if (items == null) return [];
      return DataItemModel.listFromJson(items);
    } catch (e) {
      AppLogger.error('Failed to parse items: $e');
      return [];
    }
  }

  String _friendlyError(Object error) {
    if (error is app_exc.SocketConnectionException) {
      return 'Unable to connect. Check host/port and network connection.';
    }
    if (error is app_exc.SocketNotConnectedException) {
      return 'Not connected. Please connect first.';
    }
    if (error is app_exc.SocketAuthException) {
      return 'Authentication failed. Token may be expired.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  @override
  Future<void> close() async {
    await _statusSub?.cancel();
    await _messagesSub?.cancel();
    await _disconnectUseCase();
    return super.close();
  }
}
