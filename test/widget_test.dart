// test/presentation/bloc/socket_bloc_test.dart
//
// Unit test untuk SocketBloc menggunakan bloc_test dan mocktail.
//
// Testing strategy:
//   - Setiap event di-test secara terisolasi
//   - Repository di-mock → test tidak butuh koneksi nyata
//   - Verify state transitions yang diharapkan

import 'dart:async';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:socket_demo/domain/entities/socket_message.dart';
import 'package:socket_demo/domain/repositories/socket_repository.dart';
import 'package:socket_demo/domain/usecases/socket_usecases.dart';
import 'package:socket_demo/presentation/bloc/socket_bloc.dart';
import 'package:socket_demo/presentation/bloc/socket_event.dart';
import 'package:socket_demo/presentation/bloc/socket_state.dart';

// ─── Mock Classes ─────────────────────────────────────────────────────────────
class MockConnectUseCase     extends Mock implements ConnectSocketUseCase {}
class MockDisconnectUseCase  extends Mock implements DisconnectSocketUseCase {}
class MockSendCommandUseCase extends Mock implements SendCommandUseCase {}
class MockWatchStatusUseCase extends Mock implements WatchConnectionStatusUseCase {}
class MockWatchMsgsUseCase   extends Mock implements WatchIncomingMessagesUseCase {}

void main() {
  late MockConnectUseCase      mockConnect;
  late MockDisconnectUseCase   mockDisconnect;
  late MockSendCommandUseCase  mockSendCommand;
  late MockWatchStatusUseCase  mockWatchStatus;
  late MockWatchMsgsUseCase    mockWatchMessages;

  // Stream controllers untuk simulate stream dari repository
  late StreamController<ConnectionStatus> statusController;
  late StreamController<SocketMessage>    messagesController;

  setUp(() {
    mockConnect      = MockConnectUseCase();
    mockDisconnect   = MockDisconnectUseCase();
    mockSendCommand  = MockSendCommandUseCase();
    mockWatchStatus  = MockWatchStatusUseCase();
    mockWatchMessages = MockWatchMsgsUseCase();

    statusController   = StreamController<ConnectionStatus>.broadcast();
    messagesController = StreamController<SocketMessage>.broadcast();

    // Setup default stream behavior
    when(() => mockWatchStatus()).thenAnswer((_) => statusController.stream);
    when(() => mockWatchMessages()).thenAnswer((_) => messagesController.stream);
    when(() => mockDisconnect()).thenAnswer((_) async {});
  });

  tearDown(() {
    statusController.close();
    messagesController.close();
  });

  // Helper untuk membuat BLoC dengan mock
  SocketBloc buildBloc() => SocketBloc(
    connectUseCase:      mockConnect,
    disconnectUseCase:   mockDisconnect,
    sendCommandUseCase:  mockSendCommand,
    watchStatusUseCase:  mockWatchStatus,
    watchMessagesUseCase: mockWatchMessages,
  );

  group('SocketBloc', () {
    // ── Test: state awal ────────────────────────────────────────────────────
    test('initial state is SocketState.initial()', () {
      expect(buildBloc().state, SocketState.initial());
    });

    // ── Test: connect berhasil ───────────────────────────────────────────────
    blocTest<SocketBloc, SocketState>(
      'emits connected state when connect succeeds',
      build: () {
        when(() => mockConnect(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) {
        bloc.add(const SocketConnectRequested(token: 'test-token'));
        // Simulate stream emitting connected status
        statusController.add(ConnectionStatus.connected);
      },
      expect: () => [
        // State setelah stream emit connected
        isA<SocketState>().having(
              (s) => s.connectionStatus,
          'connectionStatus',
          ConnectionStatus.connected,
        ),
      ],
    );

    // ── Test: send command berhasil ──────────────────────────────────────────
    blocTest<SocketBloc, SocketState>(
      'emits success state with items after command "001"',
      build: () {
        when(() => mockSendCommand('001', payload: any(named: 'payload')))
            .thenAnswer((_) async => const SocketMessage(
          requestId: 'test-id',
          type:      MessageType.dataResponse,
          command:   '001',
          data: {
            'items': [
              {'id': 'A', 'name': 'Data Alpha', 'value': 42, 'category': 'primary'}
            ],
            'matched': ['A'],
          },
          timestamp: 0,
        ));
        return buildBloc()
          ..emit(buildBloc().state.copyWith(
            connectionStatus: ConnectionStatus.connected,
          ));
      },
      seed: () => const SocketState(connectionStatus: ConnectionStatus.connected),
      act: (bloc) => bloc.add(const SocketCommandSent(command: '001')),
      expect: () => [
        // State saat sending
        isA<SocketState>().having(
              (s) => s.commandStatus, 'commandStatus', CommandStatus.sending,
        ),
        // State setelah sukses — ada 1 item
        isA<SocketState>()
            .having((s) => s.commandStatus, 'commandStatus', CommandStatus.success)
            .having((s) => s.receivedItems.length, 'items count', 1),
      ],
    );

    // ── Test: reconnect counter bertambah ────────────────────────────────────
    blocTest<SocketBloc, SocketState>(
      'increments reconnect counter on reconnecting status',
      build: () => buildBloc(),
      act: (bloc) {
        statusController.add(ConnectionStatus.reconnecting);
        statusController.add(ConnectionStatus.reconnecting);
      },
      expect: () => [
        isA<SocketState>()
            .having((s) => s.reconnectAttempts, 'attempts', 1),
        isA<SocketState>()
            .having((s) => s.reconnectAttempts, 'attempts', 2),
      ],
    );
  });
}