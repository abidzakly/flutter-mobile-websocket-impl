// lib/presentation/bloc/socket_state.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION LAYER — BLoC States
// ─────────────────────────────────────────────────────────────────────────────
//
// State merepresentasikan "output" dari BLoC — data yang ditampilkan di UI.
//
// Pendekatan: SATU state class dengan field status (vs banyak subclass).
// Ini lebih mudah untuk copyWith dan menghindari casting di widget.
//
// State bersifat immutable — setiap perubahan membuat instance baru.
// Flutter/BLoC menggunakan perbandingan == untuk menentukan apakah UI perlu rebuild.

import 'package:equatable/equatable.dart';
import '../../domain/entities/socket_message.dart';
import '../../domain/entities/data_item.dart';
import '../../domain/repositories/socket_repository.dart';

/// Status operasi kirim command
enum CommandStatus {
  idle,
  sending,
  success,
  failure,
}

/// [SocketState] — satu-satunya state class untuk SocketBloc.
///
/// Semua field yang dibutuhkan UI ada di sini.
/// UI tinggal bind ke field yang relevan.
class SocketState extends Equatable {
  // ─── Koneksi ───────────────────────────────────────────────────────────────
  /// Status koneksi saat ini
  final ConnectionStatus connectionStatus;

  /// Jumlah percobaan reconnect yang sudah dilakukan
  final int reconnectAttempts;

  // ─── Command / Send ────────────────────────────────────────────────────────
  /// Status pengiriman command terakhir
  final CommandStatus commandStatus;

  /// Command terakhir yang dikirim (untuk indikator loading di UI)
  final String? lastSentCommand;

  // ─── Data Lokal ────────────────────────────────────────────────────────────
  /// Data items yang terakhir diterima dari server
  /// Diupdate setiap kali respons DATA_RESPONSE diterima
  final List<DataItem> receivedItems;

  /// History semua pesan yang diterima (untuk debug / log panel)
  final List<SocketMessage> messageHistory;

  // ─── Error ─────────────────────────────────────────────────────────────────
  /// Pesan error terakhir (null jika tidak ada error)
  final String? errorMessage;

  const SocketState({
    this.connectionStatus    = ConnectionStatus.idle,
    this.reconnectAttempts   = 0,
    this.commandStatus       = CommandStatus.idle,
    this.lastSentCommand,
    this.receivedItems       = const [],
    this.messageHistory      = const [],
    this.errorMessage,
  });

  /// State awal — sebelum apapun terjadi
  factory SocketState.initial() => const SocketState();

  /// Computed property: apakah sedang terhubung?
  bool get isConnected => connectionStatus == ConnectionStatus.connected;

  /// Computed property: apakah UI harus disable tombol send?
  bool get canSendCommand =>
      isConnected && commandStatus != CommandStatus.sending;

  /// Computed property: apakah sedang dalam proses reconnect?
  bool get isReconnecting => connectionStatus == ConnectionStatus.reconnecting;

  /// Buat salinan state dengan beberapa field diubah (immutable update)
  SocketState copyWith({
    ConnectionStatus? connectionStatus,
    int? reconnectAttempts,
    CommandStatus? commandStatus,
    String? lastSentCommand,
    List<DataItem>? receivedItems,
    List<SocketMessage>? messageHistory,
    String? errorMessage,
    bool clearError = false,  // Helper untuk menghapus error
  }) {
    return SocketState(
      connectionStatus:  connectionStatus  ?? this.connectionStatus,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      commandStatus:     commandStatus     ?? this.commandStatus,
      lastSentCommand:   lastSentCommand   ?? this.lastSentCommand,
      receivedItems:     receivedItems     ?? this.receivedItems,
      messageHistory:    messageHistory    ?? this.messageHistory,
      errorMessage:      clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
    connectionStatus,
    reconnectAttempts,
    commandStatus,
    lastSentCommand,
    receivedItems,
    messageHistory,
    errorMessage,
  ];
}