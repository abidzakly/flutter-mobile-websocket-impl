// lib/domain/repositories/socket_repository.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// DOMAIN LAYER — Repository Interface (Abstract)
// ─────────────────────────────────────────────────────────────────────────────
//
// Repository interface mendefinisikan KONTRAK yang harus dipenuhi oleh
// implementasi di Data Layer.
//
// Domain Layer HANYA mengetahui interface ini — tidak tahu apakah
// implementasinya menggunakan WebSocket, HTTP, atau mock.
// Ini memungkinkan:
//   1. Testing tanpa server nyata (MockSocketRepository)
//   2. Mudah ganti implementasi tanpa ubah business logic
//   3. Dependency Inversion Principle terpenuhi

import '../../domain/entities/socket_message.dart';

/// Kontrak lengkap operasi WebSocket dari sudut pandang domain.
abstract class SocketRepository {
  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  /// Membangun koneksi WebSocket ke server.
  ///
  /// [token] — JWT untuk autentikasi pada handshake.
  /// Throws [SocketException] jika koneksi gagal.
  Future<void> connect(String token);

  /// Menutup koneksi WebSocket secara graceful.
  Future<void> disconnect();

  // ─── State ──────────────────────────────────────────────────────────────────

  /// Stream status koneksi saat ini.
  /// Emit value baru setiap kali koneksi berubah (connected/disconnected/error).
  Stream<ConnectionStatus> get connectionStatus;

  // ─── Messaging ──────────────────────────────────────────────────────────────

  /// Kirim pesan command ke server.
  ///
  /// [message] harus memiliki type == MessageType.command.
  /// Returns [Future<void>] — konfirmasi bahwa pesan sudah masuk ke send buffer.
  ///
  /// Untuk "pastikan data terkirim", gunakan [sendWithAck] yang menunggu
  /// respons eksplisit dari server dengan requestId yang sama.
  Future<void> send(SocketMessage message);

  /// Kirim pesan dan tunggu respons dari server (request-response pattern).
  ///
  /// [timeout] — batas waktu menunggu respons (default: 10 detik).
  /// Throws [TimeoutException] jika server tidak merespons.
  /// Throws [SocketException] jika koneksi terputus sebelum respons datang.
  Future<SocketMessage> sendWithAck(
      SocketMessage message, {
        Duration timeout = const Duration(seconds: 10),
      });

  /// Stream semua pesan masuk dari server.
  /// Consumer (BLoC) mendengarkan stream ini untuk update real-time.
  Stream<SocketMessage> get incomingMessages;
}

/// Status koneksi WebSocket.
enum ConnectionStatus {
  /// Proses awal, belum pernah konek
  idle,

  /// Sedang mencoba terhubung
  connecting,

  /// Koneksi aktif dan siap
  connected,

  /// Koneksi terputus (normal atau tidak)
  disconnected,

  /// Sedang mencoba reconnect
  reconnecting,

  /// Error fatal — membutuhkan intervensi pengguna
  error,
}