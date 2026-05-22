// lib/core/constants/socket_constants.dart

class SocketConstants {
  SocketConstants._();

  // ─── WebSocket Server ─────────────────────────────────────────────────────
  // Development: ws://  |  Production: wss://
  static const wsServerUrl = 'ws://10.10.4.160:8080';
  // static const wsServerUrl = 'wss://your-ngrok-subdomain.ngrok-free.app';

  // ─── Raw TCP Socket Server ────────────────────────────────────────────────
  static const tcpServerHost = '10.10.4.160';
  static const tcpServerPort = 9000;
  // For ngrok TCP tunnel: tcpServerHost = '0.tcp.ngrok.io', tcpServerPort = <assigned>

  // ─── Framing Protokol (Raw TCP only) ─────────────────────────────────────
  static const headerSize      = 4;           // 4-byte UINT32 BE length prefix
  static const maxPayloadBytes = 1024 * 1024; // 1 MB max

  // ─── Timeouts (shared) ───────────────────────────────────────────────────
  static const connectionTimeout        = Duration(seconds: 15);
  static const connectionTimeoutSeconds = 15;
  static const ackTimeout               = Duration(seconds: 10);
  static const authTimeout              = Duration(seconds: 10);

  // ─── Reconnect (shared) ──────────────────────────────────────────────────
  static const maxReconnectAttempts      = 5;
  static const reconnectBaseDelaySeconds = 1;
  static const maxReconnectDelaySeconds  = 30;

  // ─── Heartbeat ───────────────────────────────────────────────────────────
  static const clientHeartbeatInterval = Duration(seconds: 25);

  // ─── Client Metadata ─────────────────────────────────────────────────────
  static const clientVersion = '1.0.0';

  // ─── Demo Token ──────────────────────────────────────────────────────────
  static const demoJwtToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJ1c2VySWQiOiJ1c2VyXzEyMyIsImlhdCI6MTc3OTM3MDI4MiwiZXhwIjoxODEwOTA2MjgyfQ'
      '.VSPn6LHMUUZsAmuAiryfYy0y7NQMfAl_5Ddo840N0Us';
}
