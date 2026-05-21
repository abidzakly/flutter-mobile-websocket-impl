// lib/core/constants/socket_constants.dart
//
// Semua konstanta yang digunakan di seluruh aplikasi.
// Sentralisasi di sini agar mudah diubah.

class SocketConstants {
  SocketConstants._(); // Prevent instantiation

  // ─── Server URL ─────────────────────────────────────────────────────────────
  // Development: ws:// (tidak terenkripsi, hanya untuk lokal)
  // Production:  wss:// (TLS, WAJIB)
  static const serverUrl = 'wss://trivial-return-planner.ngrok-free.dev';
  // static const serverUrl = 'wss://your-production-server.com';

  // ─── Timeouts ────────────────────────────────────────────────────────────────
  static const connectionTimeout        = Duration(seconds: 15);
  static const connectionTimeoutSeconds = 15;
  static const ackTimeout               = Duration(seconds: 10);

  // ─── Reconnect ───────────────────────────────────────────────────────────────
  static const maxReconnectAttempts     = 5;
  static const reconnectBaseDelaySeconds = 1;   // Base delay: 1 detik
  static const maxReconnectDelaySeconds  = 30;  // Max delay: 30 detik

  // ─── Client Metadata ─────────────────────────────────────────────────────────
  static const clientVersion = '1.0.0';

  // ─── Demo Token ──────────────────────────────────────────────────────────────
  // HANYA UNTUK DEMO — di production ambil dari auth service / secure storage
  // Token ini harus di-generate oleh server dengan JWT_SECRET yang sesuai
  static const demoJwtToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiJ1c2VyXzEyMyIsImlhdCI6MTc3OTM3MDI4MiwiZXhwIjoxODEwOTA2MjgyfQ.VSPn6LHMUUZsAmuAiryfYy0y7NQMfAl_5Ddo840N0Us';
}
