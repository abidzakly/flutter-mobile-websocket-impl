// lib/presentation/pages/socket_page.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PRESENTATION LAYER — Main UI Page
// ─────────────────────────────────────────────────────────────────────────────
//
// Halaman utama yang menampilkan:
//   - Status koneksi (dengan warna dan animasi)
//   - Tombol connect/disconnect
//   - Tombol kirim command ("001", "011", "111")
//   - List data items yang diterima
//   - Log history pesan
//   - Error banner saat ada masalah
//
// Widget hanya bertugas menampilkan state dan dispatch event.
// TIDAK ADA business logic di sini.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/socket_constants.dart';
import '../../domain/repositories/socket_repository.dart';
import '../bloc/socket_bloc.dart';
import '../bloc/socket_event.dart';
import '../bloc/socket_state.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/command_button_panel.dart';
import '../widgets/data_items_list.dart';
import '../widgets/message_log_panel.dart';

class SocketPage extends StatelessWidget {
  const SocketPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket Demo'),
        actions: [
          // Status indicator di AppBar
          BlocBuilder<SocketBloc, SocketState>(
            buildWhen: (prev, curr) =>
            prev.connectionStatus != curr.connectionStatus,
            builder: (_, state) => ConnectionStatusIndicator(
              status: state.connectionStatus,
              compact: true,
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: BlocConsumer<SocketBloc, SocketState>(
        // listenWhen: hanya dengarkan perubahan error untuk snackbar
        listenWhen: (prev, curr) => prev.errorMessage != curr.errorMessage,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: Theme.of(context).colorScheme.error,
                action: SnackBarAction(
                  label: 'Dismiss',
                  textColor: Colors.white,
                  onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
                ),
              ),
            );
          }
        },
        builder: (context, state) {
          return RefreshIndicator(
            // Pull-to-refresh untuk reconnect manual
            onRefresh: () async {
              context.read<SocketBloc>().add(const SocketReconnectRequested());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Section 1: Koneksi ──────────────────────────────────────
                _SectionCard(
                  title: 'Connection',
                  child: Column(
                    children: [
                      ConnectionStatusIndicator(
                        status: state.connectionStatus,
                        reconnectAttempts: state.reconnectAttempts,
                      ),
                      const SizedBox(height: 16),
                      _ConnectionActions(state: state),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Section 2: Kirim Command ─────────────────────────────────
                _SectionCard(
                  title: 'Send Command',
                  child: CommandButtonPanel(
                    isEnabled: state.canSendCommand,
                    isSending: state.commandStatus == CommandStatus.sending,
                    lastCommand: state.lastSentCommand,
                    onCommand: (command) {
                      context.read<SocketBloc>().add(
                        SocketCommandSent(command: command),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // ── Section 3: Data Lokal ─────────────────────────────────────
                if (state.receivedItems.isNotEmpty) ...[
                  _SectionCard(
                    title: 'Received Data (${state.receivedItems.length} items)',
                    child: DataItemsList(items: state.receivedItems),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Section 4: Message Log ────────────────────────────────────
                _SectionCard(
                  title: 'Message Log (${state.messageHistory.length})',
                  child: MessageLogPanel(messages: state.messageHistory),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Sub-widget: Tombol Connect / Disconnect ──────────────────────────────────
class _ConnectionActions extends StatelessWidget {
  final SocketState state;
  const _ConnectionActions({required this.state});

  @override
  Widget build(BuildContext context) {
    final isConnected = state.connectionStatus == ConnectionStatus.connected;
    final isConnecting = state.connectionStatus == ConnectionStatus.connecting ||
        state.connectionStatus == ConnectionStatus.reconnecting;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isConnected || isConnecting
                ? null
                : () => context.read<SocketBloc>().add(
              SocketConnectRequested(
                // Di production: ambil token dari secure storage
                token: SocketConstants.demoJwtToken,
              ),
            ),
            icon: isConnecting
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.link),
            label: Text(isConnecting ? 'Connecting...' : 'Connect'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isConnected
                ? () => context.read<SocketBloc>().add(
              const SocketDisconnectRequested(),
            )
                : null,
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
          ),
        ),
      ],
    );
  }
}

// ─── Sub-widget: Card pembungkus section ──────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }
}