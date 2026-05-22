// test/presentation/bloc/socket_bloc_test.dart
//
// Unit test untuk SocketBloc menggunakan bloc_test dan mocktail.
//
// Testing strategy:
//   - Setiap event di-test secara terisolasi
//   - Repository di-mock → test tidak butuh koneksi nyata
//   - BLoC yang sama di-share untuk WS dan TCP karena hanya berbeda di datasource
//   - Verify state transitions dan guard conditions

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:socket_demo/core/errors/socket_exceptions.dart'
    as app_exc;
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

// ─── Fake fallback values (required by mocktail for non-primitive types) ──────
class FakeSocketMessage extends Fake implements SocketMessage {}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// A successful DATA_RESPONSE for command "001" (returns Data A).
SocketMessage _makeDataResponse({
  String command = '001',
  List<Map<String, dynamic>>? items,
  List<String>? matched,
}) {
  return SocketMessage(
    requestId: 'test-request-id',
    type:      MessageType.dataResponse,
    command:   command,
    data: {
      'items': items ??
          [
            {
              'id':          'A',
              'name':        'Data Alpha',
              'value':       100,
              'category':    'primary',
              'description': 'Sensor suhu utama',
            }
          ],
      'matched':    matched ?? ['A'],
      'totalCount': (items ?? [null]).length,
    },
    timestamp: 0,
  );
}

/// Seed state: connected, idle — represents a ready-to-send state.
SocketState get _connectedState => SocketState.initial().copyWith(
      connectionStatus: ConnectionStatus.connected,
    );

void main() {
  // ── Fallback registration (mocktail requirement for custom types) ────────────
  setUpAll(() {
    registerFallbackValue(FakeSocketMessage());
  });

  // ── Per-test state ──────────────────────────────────────────────────────────
  late MockConnectUseCase      mockConnect;
  late MockDisconnectUseCase   mockDisconnect;
  late MockSendCommandUseCase  mockSendCommand;
  late MockWatchStatusUseCase  mockWatchStatus;
  late MockWatchMsgsUseCase    mockWatchMessages;

  late StreamController<ConnectionStatus> statusController;
  late StreamController<SocketMessage>    messagesController;

  setUp(() {
    mockConnect       = MockConnectUseCase();
    mockDisconnect    = MockDisconnectUseCase();
    mockSendCommand   = MockSendCommandUseCase();
    mockWatchStatus   = MockWatchStatusUseCase();
    mockWatchMessages = MockWatchMsgsUseCase();

    statusController   = StreamController<ConnectionStatus>.broadcast();
    messagesController = StreamController<SocketMessage>.broadcast();

    // Default stream stubs — every BLoC constructor subscribes to these
    when(() => mockWatchStatus()).thenAnswer((_) => statusController.stream);
    when(() => mockWatchMessages()).thenAnswer((_) => messagesController.stream);

    // Default disconnect stub (called in BLoC.close())
    when(() => mockDisconnect()).thenAnswer((_) async {});
  });

  tearDown(() {
    statusController.close();
    messagesController.close();
  });

  // Helper: build a fresh BLoC wired to all mocks
  SocketBloc buildBloc() => SocketBloc(
        connectUseCase:       mockConnect,
        disconnectUseCase:    mockDisconnect,
        sendCommandUseCase:   mockSendCommand,
        watchStatusUseCase:   mockWatchStatus,
        watchMessagesUseCase: mockWatchMessages,
      );

  // ══════════════════════════════════════════════════════════════════════════
  // Initial state
  // ══════════════════════════════════════════════════════════════════════════
  group('Initial state', () {
    test('starts as SocketState.initial()', () {
      expect(buildBloc().state, equals(SocketState.initial()));
    });

    test('connectionStatus is idle', () {
      expect(
        buildBloc().state.connectionStatus,
        equals(ConnectionStatus.idle),
      );
    });

    test('canSendCommand is false when idle', () {
      expect(buildBloc().state.canSendCommand, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Connect
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketConnectRequested', () {
    blocTest<SocketBloc, SocketState>(
      'calls connect use case and reflects connected status from stream',
      build: () {
        when(() => mockConnect(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(const SocketConnectRequested('test-token'));
        // Simulate datasource emitting connected after handshake
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.connected);
      },
      expect: () => [
        isA<SocketState>().having(
          (s) => s.connectionStatus,
          'connectionStatus',
          ConnectionStatus.connected,
        ),
      ],
      verify: (_) {
        // connect() was called with the provided token
        verify(() => mockConnect('test-token')).called(1);
      },
    );

    blocTest<SocketBloc, SocketState>(
      'emits error state when connect throws',
      build: () {
        when(() => mockConnect(any())).thenThrow(
          const app_exc.SocketConnectionException('Host unreachable'),
        );
        return buildBloc();
      },
      act: (bloc) => bloc.add(const SocketConnectRequested('bad-token')),
      expect: () => [
        isA<SocketState>()
            .having((s) => s.connectionStatus, 'status', ConnectionStatus.error)
            .having((s) => s.errorMessage,      'error',  isNotNull),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'clears previous errorMessage on new connect attempt',
      build: () {
        when(() => mockConnect(any())).thenAnswer((_) async {});
        return buildBloc();
      },
      seed: () => SocketState.initial().copyWith(
        errorMessage: 'Previous error',
      ),
      act: (bloc) => bloc.add(const SocketConnectRequested('token')),
      expect: () => [
        isA<SocketState>().having((s) => s.errorMessage, 'error', isNull),
      ],
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Disconnect
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketDisconnectRequested', () {
    blocTest<SocketBloc, SocketState>(
      'calls disconnect use case',
      build: () => buildBloc(),
      act: (bloc) => bloc.add(const SocketDisconnectRequested()),
      verify: (_) {
        verify(() => mockDisconnect()).called(
          // BLoC.close() also calls disconnect — so at least 1 call here
          greaterThanOrEqualTo(1),
        );
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Send Command
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketCommandSent', () {
    blocTest<SocketBloc, SocketState>(
      'emits sending → success with 1 item for command "001"',
      build: () {
        when(
          () => mockSendCommand('001', payload: any(named: 'payload')),
        ).thenAnswer((_) async => _makeDataResponse());
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('001')),
      expect: () => [
        // 1st emit: sending
        isA<SocketState>()
            .having((s) => s.commandStatus,   'commandStatus', CommandStatus.sending)
            .having((s) => s.lastSentCommand, 'lastCommand',   '001'),
        // 2nd emit: success with parsed items
        isA<SocketState>()
            .having((s) => s.commandStatus,       'commandStatus', CommandStatus.success)
            .having((s) => s.receivedItems.length, 'itemCount',     1)
            .having((s) => s.receivedItems.first.id, 'itemId',      'A'),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'emits success with 2 items for command "011" (A and B)',
      build: () {
        when(
          () => mockSendCommand('011', payload: any(named: 'payload')),
        ).thenAnswer(
          (_) async => _makeDataResponse(
            command: '011',
            items: [
              {'id': 'A', 'name': 'Data Alpha', 'value': 100, 'category': 'primary'},
              {'id': 'B', 'name': 'Data Beta',  'value': 200, 'category': 'secondary'},
            ],
            matched: ['A', 'B'],
          ),
        );
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('011')),
      expect: () => [
        isA<SocketState>().having((s) => s.commandStatus, 'status', CommandStatus.sending),
        isA<SocketState>()
            .having((s) => s.commandStatus,       'status',    CommandStatus.success)
            .having((s) => s.receivedItems.length, 'itemCount', 2),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'emits success with 3 items for command "111" (A, B, and C)',
      build: () {
        when(
          () => mockSendCommand('111', payload: any(named: 'payload')),
        ).thenAnswer(
          (_) async => _makeDataResponse(
            command: '111',
            items: [
              {'id': 'A', 'name': 'Data Alpha', 'value': 100, 'category': 'primary'},
              {'id': 'B', 'name': 'Data Beta',  'value': 200, 'category': 'secondary'},
              {'id': 'C', 'name': 'Data Gamma', 'value': 300, 'category': 'tertiary'},
            ],
            matched: ['A', 'B', 'C'],
          ),
        );
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('111')),
      expect: () => [
        isA<SocketState>().having((s) => s.commandStatus, 'status', CommandStatus.sending),
        isA<SocketState>()
            .having((s) => s.commandStatus,       'status',    CommandStatus.success)
            .having((s) => s.receivedItems.length, 'itemCount', 3),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'adds response to messageHistory after success',
      build: () {
        when(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).thenAnswer((_) async => _makeDataResponse());
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('001')),
      expect: () => [
        isA<SocketState>().having((s) => s.commandStatus, 'status', CommandStatus.sending),
        isA<SocketState>()
            .having((s) => s.messageHistory.length, 'historyCount', 1),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'emits failure with message on timeout',
      build: () {
        when(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).thenThrow(
          const app_exc.SocketTimeoutException('Request timed out'),
        );
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('001')),
      expect: () => [
        isA<SocketState>().having((s) => s.commandStatus, 'status', CommandStatus.sending),
        isA<SocketState>()
            .having((s) => s.commandStatus, 'status', CommandStatus.failure)
            .having((s) => s.errorMessage,  'error',  isNotNull),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'emits failure with message on server error',
      build: () {
        when(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).thenThrow(
          const app_exc.SocketServerException('Unknown command'),
        );
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) => bloc.add(const SocketCommandSent('999')),
      expect: () => [
        isA<SocketState>().having((s) => s.commandStatus, 'status', CommandStatus.sending),
        isA<SocketState>()
            .having((s) => s.commandStatus, 'status', CommandStatus.failure)
            .having(
              (s) => s.errorMessage,
              'error',
              contains('Server error'),
            ),
      ],
    );

    // ── Guard: canSendCommand ────────────────────────────────────────────────
    blocTest<SocketBloc, SocketState>(
      'ignores command when not connected (canSendCommand guard)',
      build: () => buildBloc(), // seed is initial (idle/disconnected)
      act: (bloc) => bloc.add(const SocketCommandSent('001')),
      expect: () => <SocketState>[], // no state change
      verify: (_) {
        // sendCommandUseCase must NOT have been called
        verifyNever(() => mockSendCommand(any(), payload: any(named: 'payload')));
      },
    );

    blocTest<SocketBloc, SocketState>(
      'ignores second command while first is already sending',
      build: () {
        final completer = Completer<SocketMessage>();
        when(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).thenAnswer((_) => completer.future); // never completes
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) async {
        bloc.add(const SocketCommandSent('001'));
        await Future<void>.delayed(Duration.zero);
        // State is now CommandStatus.sending — this should be ignored
        bloc.add(const SocketCommandSent('011'));
      },
      expect: () => [
        isA<SocketState>().having(
          (s) => s.commandStatus, 'commandStatus', CommandStatus.sending,
        ),
        // No second sending state — second command was blocked
      ],
      verify: (_) {
        // sendCommandUseCase was only called once
        verify(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).called(1);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Connection status stream
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketConnectionStatusChanged (from stream)', () {
    blocTest<SocketBloc, SocketState>(
      'reflects each status from the stream',
      build: () => buildBloc(),
      act: (bloc) async {
        statusController.add(ConnectionStatus.connecting);
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.connected);
      },
      expect: () => [
        isA<SocketState>().having(
          (s) => s.connectionStatus, 'status', ConnectionStatus.connecting,
        ),
        isA<SocketState>().having(
          (s) => s.connectionStatus, 'status', ConnectionStatus.connected,
        ),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'increments reconnectAttempts on each reconnecting status',
      build: () => buildBloc(),
      act: (bloc) async {
        statusController.add(ConnectionStatus.reconnecting);
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.reconnecting);
        await Future<void>.delayed(Duration.zero);
        statusController.add(ConnectionStatus.reconnecting);
      },
      expect: () => [
        isA<SocketState>().having((s) => s.reconnectAttempts, 'attempts', 1),
        isA<SocketState>().having((s) => s.reconnectAttempts, 'attempts', 2),
        isA<SocketState>().having((s) => s.reconnectAttempts, 'attempts', 3),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'clears errorMessage when status becomes connected',
      build: () => buildBloc(),
      seed: () => SocketState.initial().copyWith(errorMessage: 'Some error'),
      act: (bloc) => statusController.add(ConnectionStatus.connected),
      expect: () => [
        isA<SocketState>()
            .having((s) => s.connectionStatus, 'status', ConnectionStatus.connected)
            .having((s) => s.errorMessage,      'error',  isNull),
      ],
    );

    // TCP-specific: authenticating status
    blocTest<SocketBloc, SocketState>(
      'reflects authenticating status (Raw TCP only)',
      build: () => buildBloc(),
      act: (bloc) => statusController.add(ConnectionStatus.authenticating),
      expect: () => [
        isA<SocketState>().having(
          (s) => s.connectionStatus, 'status', ConnectionStatus.authenticating,
        ),
      ],
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Incoming messages (server-push)
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketMessageReceived (server-push)', () {
    blocTest<SocketBloc, SocketState>(
      'updates receivedItems from unsolicited DATA_RESPONSE',
      build: () => buildBloc(),
      act: (bloc) => messagesController.add(_makeDataResponse()),
      expect: () => [
        isA<SocketState>()
            .having((s) => s.receivedItems.length, 'itemCount', 1)
            .having((s) => s.receivedItems.first.id, 'itemId', 'A'),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'appends message to history for non-data messages',
      build: () => buildBloc(),
      act: (bloc) => messagesController.add(
        const SocketMessage(
          requestId: 'r1',
          type:      MessageType.error,
          errorCode: 'SOME_ERROR',
          errorMessage: 'Something went wrong',
          timestamp: 0,
        ),
      ),
      expect: () => [
        isA<SocketState>().having(
          (s) => s.messageHistory.length, 'historyCount', 1,
        ),
      ],
    );

    blocTest<SocketBloc, SocketState>(
      'replaces receivedItems (not appends) on each new DATA_RESPONSE',
      build: () {
        when(
          () => mockSendCommand(any(), payload: any(named: 'payload')),
        ).thenAnswer((_) async => _makeDataResponse());
        return buildBloc();
      },
      seed: () => _connectedState,
      act: (bloc) async {
        // First command: 1 item
        bloc.add(const SocketCommandSent('001'));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Server push: 2 items (e.g. from another command or broadcast)
        messagesController.add(
          _makeDataResponse(
            command: '011',
            items: [
              {'id': 'A', 'name': 'Data Alpha', 'value': 100, 'category': 'primary'},
              {'id': 'B', 'name': 'Data Beta',  'value': 200, 'category': 'secondary'},
            ],
            matched: ['A', 'B'],
          ),
        );
      },
      verify: (bloc) {
        // Final items should be 2 (latest server-push), not 1+2
        expect(bloc.state.receivedItems.length, 2);
      },
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Reconnect
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketReconnectRequested', () {
    blocTest<SocketBloc, SocketState>(
      'resets reconnectAttempts to 0',
      build: () => buildBloc(),
      seed: () => SocketState.initial().copyWith(
        reconnectAttempts: 3,
        connectionStatus:  ConnectionStatus.error,
      ),
      act: (bloc) => bloc.add(const SocketReconnectRequested()),
      expect: () => [
        isA<SocketState>().having(
          (s) => s.reconnectAttempts, 'attempts', 0,
        ),
      ],
    );
  });

  // ══════════════════════════════════════════════════════════════════════════
  // Computed properties
  // ══════════════════════════════════════════════════════════════════════════
  group('SocketState computed properties', () {
    test('isConnected is true only when connected', () {
      final s = SocketState.initial().copyWith(
        connectionStatus: ConnectionStatus.connected,
      );
      expect(s.isConnected, isTrue);
    });

    test('isConnecting is true for connecting AND authenticating', () {
      expect(
        SocketState.initial()
            .copyWith(connectionStatus: ConnectionStatus.connecting)
            .isConnecting,
        isTrue,
      );
      expect(
        SocketState.initial()
            .copyWith(connectionStatus: ConnectionStatus.authenticating)
            .isConnecting,
        isTrue,
      );
    });

    test('canSendCommand is false when commandStatus is sending', () {
      final s = SocketState.initial().copyWith(
        connectionStatus: ConnectionStatus.connected,
        commandStatus:    CommandStatus.sending,
      );
      expect(s.canSendCommand, isFalse);
    });

    test('canSendCommand is true when connected and idle', () {
      expect(_connectedState.canSendCommand, isTrue);
    });
  });
}
