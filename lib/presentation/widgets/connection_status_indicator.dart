// lib/presentation/widgets/connection_status_indicator.dart

import 'package:flutter/material.dart';
import '../../domain/repositories/socket_repository.dart';

/// Widget yang menampilkan status koneksi secara visual.
/// Mendukung mode compact (untuk AppBar) dan mode penuh.
class ConnectionStatusIndicator extends StatelessWidget {
  final ConnectionStatus status;
  final int reconnectAttempts;
  final bool compact;

  const ConnectionStatusIndicator({
    super.key,
    required this.status,
    this.reconnectAttempts = 0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(status);

    if (compact) {
      // Mode compact: hanya dot berwarna (untuk AppBar)
      return Tooltip(
        message: info.label,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: info.color,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    // Mode penuh: icon + label + reconnect counter
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Animasi pulsing saat connecting/reconnecting
        if (status == ConnectionStatus.connecting ||
            status == ConnectionStatus.reconnecting)
          _PulsingDot(color: info.color)
        else
          Icon(info.icon, color: info.color, size: 20),
        const SizedBox(width: 8),
        Text(
          reconnectAttempts > 0 && status == ConnectionStatus.reconnecting
              ? '${info.label} (attempt $reconnectAttempts)'
              : info.label,
          style: TextStyle(color: info.color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  _StatusInfo _statusInfo(ConnectionStatus s) {
    switch (s) {
      case ConnectionStatus.idle:
        return _StatusInfo('Not Connected', Colors.grey, Icons.circle_outlined);
      case ConnectionStatus.connecting:
        return _StatusInfo('Connecting...', Colors.orange, Icons.sync);
      case ConnectionStatus.connected:
        return _StatusInfo('Connected', Colors.green, Icons.check_circle);
      case ConnectionStatus.disconnected:
        return _StatusInfo('Disconnected', Colors.red, Icons.cancel);
      case ConnectionStatus.reconnecting:
        return _StatusInfo('Reconnecting...', Colors.orange, Icons.sync);
      case ConnectionStatus.error:
        return _StatusInfo('Connection Error', Colors.red, Icons.error);
    }
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}

/// Animasi dot pulsing untuk state connecting
class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Icon(Icons.circle, color: widget.color, size: 14),
  );
}