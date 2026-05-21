// lib/presentation/bloc/socket_bloc.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION LAYER — BLoC
// ─────────────────────────────────────────────────────────────────────────────
//
// BLoC (Business Logic Component) adalah bridge antara UI dan Domain.
//
// Alur:
//   UI dispatch Event → BLoC handle → Emit State baru → UI rebuild
//
// BLoC ini mengelola:
//   1. Lifecycle koneksi (connect/disconnect)
//   2. Kirim command dan tangani respons
//   3. Subscribe ke stream koneksi dan pesan masuk
//   4. Update state lokal (data items, history)
//   5. Error handling yang user-friendly

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/errors/socket_exceptions.dart';
import '../../core/utils/logger.dart';
import '../../data/models/socket_message_model.dart';
import '../../domain/entities/data_item.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/repositories/socket_repository.dart';
import '../../domain/usecases/socket_usecases.dart';
import 'socket_event.dart';
import 'socket_state.dart';

class SocketBloc extends Bloc<SocketEvent, SocketState> {
  // ─── Use Cases (disuntik via constructor) ────────────────────────────────────
  final ConnectSocketUseCase         _connectUseCase;
  final DisconnectSocketUseCase      _disconnectUseCase;
  final SendCommandUseCase           _sendCommandUseCase;
  final WatchConnectionStatusUseCase _watchStatusUseCase;
  final WatchIncomingMessagesUseCase _watchMessagesUseCase;

  // ─── Stream Subscriptions (harus di-cancel saat close) ─────────────────────
  StreamSubscription<ConnectionStatus>? _statusSub;
  StreamSubscription<SocketMessage>?   _messagesSub;

  SocketBloc({
    required ConnectSocketUseCase         connectUseCase,
    required DisconnectSocketUseCase      disconnectUseCase,
    required SendCommandUseCase           sendCommandUseCase,
    required WatchConnectionStatusUseCase watchStatusUseCase,
    required WatchIncomingMessagesUseCase watchMessagesUseCase,
  })  : _connectUseCase     = connectUseCase,
        _disconnectUseCase  = disconnectUseCase,
        _sendCommandUseCase = sendCommandUseCase,
        _watchStatusUseCase = watchStatusUseCase,
        _watchMessagesUseCase = watchMessagesUseCase,
        super(SocketState.initial()) {

    // Register event handlers
    on<SocketConnectRequested>        (_onConnectRequested);
    on<SocketDisconnectRequested>     (_onDisconnectRequested);
    on<SocketCommandSent>             (_onCommandSent);
    on<SocketConnectionStatusChanged> (_onConnectionStatusChanged);
    on<SocketMessageReceived>         (_onMessageReceived);
    on<SocketReconnectRequested>      (_onReconnectRequested);

    // Mulai mendengarkan stream status koneksi dan pesan masuk
    _startListening();
  }

  // ─── Private: Setup stream subscriptions ─────────────────────────────────────

  /// Subscribe ke dua stream:
  /// 1. Connection status stream → dispatch SocketConnectionStatusChanged
  /// 2. Incoming messages stream → dispatch SocketMessageReceived
  ///
  /// Stream → Event → BLoC → State adalah pattern standar untuk reactive data.
  void _startListening() {
    // Stream 1: Status koneksi
    _statusSub = _watchStatusUseCase().listen(
          (status) => add(SocketConnectionStatusChanged(status)),
      onError: (err) => AppLogger.error('Status stream error: $err'),
    );

    // Stream 2: Pesan masuk dari server
    _messagesSub = _watchMessagesUseCase().listen(
          (message) => add(SocketMessageReceived(message)),
      onError: (err) => AppLogger.error('Messages stream error: $err'),
    );
  }

  // ─── Event Handlers ──────────────────────────────────────────────────────────

  /// Tangani permintaan koneksi dari UI.
  Future<void> _onConnectRequested(
      SocketConnectRequested event,
      Emitter<SocketState> emit,
      ) async {
    AppLogger.info('BLoC: connect requested');
    try {
      emit(state.copyWith(clearError: true));
      await _connectUseCase(event.token);
      // Status update akan datang dari _statusSub stream
    } catch (e) {
      emit(state.copyWith(
        connectionStatus: ConnectionStatus.error,
        errorMessage: _friendlyError(e),
      ));
    }
  }

  /// Tangani permintaan disconnect dari UI.
  Future<void> _onDisconnectRequested(
      SocketDisconnectRequested event,
      Emitter<SocketState> emit,
      ) async {
    AppLogger.info('BLoC: disconnect requested');
    await _disconnectUseCase();
    // Status akan diupdate via stream
  }

  /// Tangani pengiriman command dari UI.
  ///
  /// Flow:
  /// 1. Emit state "sending" → UI tampilkan loading
  /// 2. Kirim command via use case (await respons / ACK)
  /// 3a. Sukses: parse data items dari respons, update state lokal
  /// 3b. Gagal: emit error state
  Future<void> _onCommandSent(
      SocketCommandSent event,
      Emitter<SocketState> emit,
      ) async {
    if (!state.canSendCommand) {
      AppLogger.warn('Command rejected: not connected or already sending');
      return;
    }

    AppLogger.info('BLoC: sending command ${event.command}');

    // Update state: sedang mengirim
    emit(state.copyWith(
      commandStatus:   CommandStatus.sending,
      lastSentCommand: event.command,
      clearError:      true,
    ));

    try {
      // Kirim command dan tunggu respons dari server
      final response = await _sendCommandUseCase(
        event.command,
        payload: event.payload,
      );

      // ── Parse data items dari respons ──────────────────────────────────────
      final newItems = _parseItemsFromResponse(response);

      // ── Update data lokal dan tambahkan ke history ─────────────────────────
      // Ini memenuhi acceptance criteria:
      // "Update data lokal dari client setelah menerima data dari server"
      final updatedHistory = [...state.messageHistory, response];

      emit(state.copyWith(
        commandStatus: CommandStatus.success,
        receivedItems: newItems,
        messageHistory: updatedHistory,
        clearError: true,
      ));

      AppLogger.info('Command ${event.command} → received ${newItems.length} items');

    } on SocketTimeoutException catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage: 'Request timed out. Please try again.',
      ));
      AppLogger.error('Command timeout: ${e.message}');

    } on SocketServerException catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage: 'Server error: ${e.message}',
      ));
      AppLogger.error('Server error: ${e.message}');

    } catch (e) {
      emit(state.copyWith(
        commandStatus: CommandStatus.failure,
        errorMessage: _friendlyError(e),
      ));
      AppLogger.error('Command failed: $e');
    }
  }

  /// Tangani perubahan status koneksi dari stream.
  void _onConnectionStatusChanged(
      SocketConnectionStatusChanged event,
      Emitter<SocketState> emit,
      ) {
    AppLogger.info('BLoC: connection status → ${event.status.name}');

    // Saat reconnecting, increment counter di state
    final reconnectAttempts = event.status == ConnectionStatus.reconnecting
        ? state.reconnectAttempts + 1
        : state.reconnectAttempts;

    emit(state.copyWith(
      connectionStatus:  event.status,
      reconnectAttempts: reconnectAttempts,
      // Reset error saat berhasil konek kembali
      clearError: event.status == ConnectionStatus.connected,
    ));
  }

  /// Tangani pesan server-push (broadcast dari server tanpa request dari client).
  void _onMessageReceived(
      SocketMessageReceived event,
      Emitter<SocketState> emit,
      ) {
    final message = event.message;
    AppLogger.debug('BLoC: server push received — type: ${message.type.name}');

    final updatedHistory = [...state.messageHistory, message];

    // Jika server-push membawa data, update data lokal juga
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

  /// Tangani permintaan reconnect manual dari UI.
  Future<void> _onReconnectRequested(
      SocketReconnectRequested event,
      Emitter<SocketState> emit,
      ) async {
    if (state.connectionStatus == ConnectionStatus.reconnecting) return;

    // Reset attempt counter saat user minta reconnect manual
    emit(state.copyWith(reconnectAttempts: 0, clearError: true));
    // Datasource sudah punya logika reconnect internal,
    // tapi untuk manual retry kita bisa reconnect langsung
    AppLogger.info('BLoC: manual reconnect requested');
  }

  // ─── Private: Helpers ─────────────────────────────────────────────────────────

  /// Parse list DataItem dari SocketMessage respons.
  List<DataItem> _parseItemsFromResponse(SocketMessage response) {
    try {
      final data  = response.data;
      if (data == null) return [];

      final items = data['items'] as List<dynamic>?;
      if (items == null) return [];

      return DataItemModel.listFromJson(items);
    } catch (e) {
      AppLogger.error('Failed to parse items: $e');
      return [];
    }
  }

  /// Konversi exception teknis ke pesan yang ramah pengguna.
  String _friendlyError(Object error) {
    if (error is SocketConnectionException) {
      return 'Unable to connect to server. Check your internet connection.';
    }
    if (error is SocketNotConnectedException) {
      return 'Not connected. Please connect first.';
    }
    return 'An unexpected error occurred. Please try again.';
  }

  // ─── Cleanup ──────────────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    // WAJIB cancel semua subscription untuk menghindari memory leak
    await _statusSub?.cancel();
    await _messagesSub?.cancel();
    await _disconnectUseCase();
    return super.close();
  }
}