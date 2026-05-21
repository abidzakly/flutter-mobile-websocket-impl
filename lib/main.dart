// lib/main.dart
//
// Entry point aplikasi Flutter.
// Urutan inisialisasi:
//   1. Pastikan Flutter binding siap
//   2. Setup Dependency Injection
//   3. runApp

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:requests_inspector/requests_inspector.dart';

import 'core/di/injection.dart';
import 'presentation/bloc/socket_bloc.dart';
import 'presentation/pages/socket_page.dart';

Future<void> main() async {
  // Wajib sebelum memanggil async code di main
  WidgetsFlutterBinding.ensureInitialized();

  // Daftarkan semua dependency
  await configureDependencies();

  runApp(const RequestsInspector(child: SocketDemoApp()));
}

class SocketDemoApp extends StatelessWidget {
  const SocketDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebSocket BLoC Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: BlocProvider(
        // BLoC disediakan di root widget agar dapat diakses
        // oleh seluruh subtree SocketPage
        create: (_) => sl<SocketBloc>(),
        child: const SocketPage(),
      ),
    );
  }
}