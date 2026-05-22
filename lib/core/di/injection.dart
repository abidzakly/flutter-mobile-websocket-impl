// lib/core/di/injection.dart
//
// Two separate dependency graphs — one for WebSocket, one for Raw TCP.
// Each page gets its own BLoC instance wired to the right datasource.
//
// Named registrations prevent collision:
//   sl<SocketBloc>(instanceName: 'ws')   → WebSocket BLoC
//   sl<SocketBloc>(instanceName: 'tcp')  → Raw TCP BLoC

import 'package:get_it/get_it.dart';

import '../../core/constants/socket_constants.dart';
import '../../data/datasources/websocket_datasource.dart';
import '../../data/datasources/raw_socket_datasource.dart';
import '../../data/repositories/socket_repository_impl.dart';
import '../../domain/repositories/socket_repository.dart';
import '../../domain/usecases/socket_usecases.dart';
import '../../presentation/bloc/socket_bloc.dart';

final sl = GetIt.instance;

Future<void> configureDependencies() async {
  // ── WebSocket stack ────────────────────────────────────────────────────────
  sl.registerLazySingleton<WebSocketDataSource>(
    () => WebSocketDataSourceImpl(
      baseUrl:    SocketConstants.wsServerUrl,
      hmacSecret: const String.fromEnvironment('HMAC_SECRET', defaultValue: ''),
    ),
  );

  sl.registerLazySingleton<SocketRepository>(
    () => WebSocketRepositoryImpl(sl<WebSocketDataSource>()),
    instanceName: 'ws',
  );

  sl.registerFactory(
    () => SocketBloc(
      connectUseCase:       ConnectSocketUseCase(sl<SocketRepository>(instanceName: 'ws')),
      disconnectUseCase:    DisconnectSocketUseCase(sl<SocketRepository>(instanceName: 'ws')),
      sendCommandUseCase:   SendCommandUseCase(sl<SocketRepository>(instanceName: 'ws')),
      watchStatusUseCase:   WatchConnectionStatusUseCase(sl<SocketRepository>(instanceName: 'ws')),
      watchMessagesUseCase: WatchIncomingMessagesUseCase(sl<SocketRepository>(instanceName: 'ws')),
    ),
    instanceName: 'ws',
  );

  // ── Raw TCP Socket stack ───────────────────────────────────────────────────
  sl.registerLazySingleton<RawSocketDataSource>(
    () => RawSocketDataSourceImpl(
      host:       SocketConstants.tcpServerHost,
      port:       SocketConstants.tcpServerPort,
      hmacSecret: const String.fromEnvironment('HMAC_SECRET', defaultValue: ''),
      useTls:     false, // set true in production
    ),
  );

  sl.registerLazySingleton<SocketRepository>(
    () => TcpSocketRepositoryImpl(sl<RawSocketDataSource>()),
    instanceName: 'tcp',
  );

  sl.registerFactory(
    () => SocketBloc(
      connectUseCase:       ConnectSocketUseCase(sl<SocketRepository>(instanceName: 'tcp')),
      disconnectUseCase:    DisconnectSocketUseCase(sl<SocketRepository>(instanceName: 'tcp')),
      sendCommandUseCase:   SendCommandUseCase(sl<SocketRepository>(instanceName: 'tcp')),
      watchStatusUseCase:   WatchConnectionStatusUseCase(sl<SocketRepository>(instanceName: 'tcp')),
      watchMessagesUseCase: WatchIncomingMessagesUseCase(sl<SocketRepository>(instanceName: 'tcp')),
    ),
    instanceName: 'tcp',
  );
}
