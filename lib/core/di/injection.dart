// lib/core/di/injection.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// Dependency Injection — Service Locator menggunakan get_it
// ─────────────────────────────────────────────────────────────────────────────
//
// Semua dependency didaftarkan di sini.
// Ini memastikan:
//   1. Single instance (singleton) untuk repository dan datasource
//   2. Mudah di-mock saat testing dengan override
//   3. Tidak ada coupling antar layer (setiap layer hanya bergantung pada interface)
//
// Cara pakai:
//   await configureDependencies();   // di main.dart sebelum runApp
//   final bloc = sl<SocketBloc>();   // anywhere

import 'package:get_it/get_it.dart';
import '../../core/constants/socket_constants.dart';
import '../../data/datasources/websocket_datasource.dart';
import '../../data/repositories/socket_repository_impl.dart';
import '../../domain/repositories/socket_repository.dart';
import '../../domain/usecases/socket_usecases.dart';
import '../../presentation/bloc/socket_bloc.dart';

/// Global service locator instance
final sl = GetIt.instance;

/// Daftarkan semua dependency.
/// Dipanggil sekali saat aplikasi start (di main.dart).
Future<void> configureDependencies() async {
  // ─── Data Sources ─────────────────────────────────────────────────────────
  // Singleton: satu instance WebSocketDataSource untuk seluruh app lifecycle
  sl.registerLazySingleton<WebSocketDataSource>(
        () => WebSocketDataSourceImpl(
      baseUrl:    SocketConstants.serverUrl,
      hmacSecret: const String.fromEnvironment('HMAC_SECRET', defaultValue: ''),
    ),
  );

  // ─── Repositories ─────────────────────────────────────────────────────────
  sl.registerLazySingleton<SocketRepository>(
        () => SocketRepositoryImpl(sl<WebSocketDataSource>()),
  );

  // ─── Use Cases ────────────────────────────────────────────────────────────
  // Use case bisa berupa factory (new instance per request) karena stateless
  sl.registerFactory(() => ConnectSocketUseCase(sl()));
  sl.registerFactory(() => DisconnectSocketUseCase(sl()));
  sl.registerFactory(() => SendCommandUseCase(sl()));
  sl.registerFactory(() => WatchConnectionStatusUseCase(sl()));
  sl.registerFactory(() => WatchIncomingMessagesUseCase(sl()));

  // ─── BLoC ─────────────────────────────────────────────────────────────────
  // Factory: setiap halaman yang butuh BLoC ini mendapat instance baru
  // (sehingga lifecycle BLoC mengikuti widget yang membukanya)
  sl.registerFactory(
        () => SocketBloc(
      connectUseCase:      sl(),
      disconnectUseCase:   sl(),
      sendCommandUseCase:  sl(),
      watchStatusUseCase:  sl(),
      watchMessagesUseCase: sl(),
    ),
  );
}