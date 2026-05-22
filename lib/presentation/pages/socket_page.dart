// lib/presentation/pages/socket_page.dart
//
// Shared page layout — used by both WebSocketPage and TcpSocketPage.
// Protocol-specific label and BLoC instance are passed as parameters.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/socket_constants.dart';
import '../bloc/socket_bloc.dart';
import '../bloc/socket_event.dart';
import '../bloc/socket_state.dart';
import '../widgets/command_button_panel.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/data_items_list.dart';
import '../widgets/message_log_panel.dart';

class SocketPage extends StatelessWidget {
  final SocketBloc bloc;
  final String     title;
  final String     protocolLabel;
  final Color      accentColor;

  const SocketPage({
    super.key,
    required this.bloc,
    required this.title,
    required this.protocolLabel,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: bloc,
      child: _SocketView(
        title:         title,
        protocolLabel: protocolLabel,
        accentColor:   accentColor,
      ),
    );
  }
}

class _SocketView extends StatelessWidget {
  final String title;
  final String protocolLabel;
  final Color  accentColor;

  const _SocketView({
    required this.title,
    required this.protocolLabel,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            Text(
              protocolLabel,
              style: TextStyle(fontSize: 11, color: accentColor),
            ),
          ],
        ),
        actions: [
          BlocBuilder<SocketBloc, SocketState>(
            buildWhen: (p, c) => p.connectionStatus != c.connectionStatus,
            builder: (context, state) {
              return IconButton(
                icon: Icon(
                  state.isConnected ? Icons.link_off : Icons.link,
                  color: state.isConnected ? accentColor : null,
                ),
                tooltip: state.isConnected ? 'Disconnect' : 'Connect',
                onPressed: state.isConnecting
                    ? null
                    : () => state.isConnected
                        ? context.read<SocketBloc>().add(
                              const SocketDisconnectRequested(),
                            )
                        : context.read<SocketBloc>().add(
                              SocketConnectRequested(
                                SocketConstants.demoJwtToken,
                              ),
                            ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          ConnectionStatusIndicator(accentColor: accentColor),

          // Error banner
          BlocBuilder<SocketBloc, SocketState>(
            buildWhen: (p, c) => p.errorMessage != c.errorMessage,
            builder: (context, state) {
              if (state.errorMessage == null) return const SizedBox.shrink();
              return MaterialBanner(
                backgroundColor: Colors.red.shade50,
                leading: const Icon(Icons.error_outline, color: Colors.red),
                content: Text(state.errorMessage!),
                actions: [
                  TextButton(
                    onPressed: () => context.read<SocketBloc>().add(
                          const SocketReconnectRequested(),
                        ),
                    child: const Text('Retry'),
                  ),
                ],
              );
            },
          ),

          CommandButtonPanel(accentColor: accentColor),
          const Divider(height: 1),
          const Expanded(flex: 2, child: DataItemsList()),
          const Divider(height: 1),
          const Expanded(flex: 3, child: MessageLogPanel()),
        ],
      ),
    );
  }
}
