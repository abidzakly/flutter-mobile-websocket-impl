// lib/presentation/widgets/connection_status_indicator.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/socket_repository.dart';
import '../bloc/socket_bloc.dart';
import '../bloc/socket_state.dart';

class ConnectionStatusIndicator extends StatelessWidget {
  final Color accentColor;
  const ConnectionStatusIndicator({super.key, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocketBloc, SocketState>(
      buildWhen: (p, c) =>
          p.connectionStatus  != c.connectionStatus ||
          p.reconnectAttempts != c.reconnectAttempts,
      builder: (context, state) {
        final (color, icon, label) = _statusDisplay(state, accentColor);
        return Container(
          color: color.withOpacity(0.10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color, fontWeight: FontWeight.w600, fontSize: 12,
                ),
              ),
              if (state.isConnecting || state.isReconnecting) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  (Color, IconData, String) _statusDisplay(SocketState state, Color accent) {
    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        return (accent, Icons.wifi, 'Connected');
      case ConnectionStatus.connecting:
        return (Colors.orange, Icons.wifi_find, 'Connecting...');
      case ConnectionStatus.authenticating:
        return (Colors.orange, Icons.lock_clock, 'Authenticating...');
      case ConnectionStatus.reconnecting:
        return (
          Colors.orange,
          Icons.wifi_protected_setup,
          'Reconnecting... (attempt ${state.reconnectAttempts})',
        );
      case ConnectionStatus.disconnected:
        return (Colors.grey, Icons.wifi_off, 'Disconnected');
      case ConnectionStatus.error:
        return (Colors.red, Icons.error_outline, 'Connection Error');
      case ConnectionStatus.idle:
        return (Colors.grey, Icons.wifi_off, 'Tap Connect to start');
    }
  }
}
