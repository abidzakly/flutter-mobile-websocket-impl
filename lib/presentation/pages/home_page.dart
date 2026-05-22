// lib/presentation/pages/home_page.dart
//
// Entry point — shows two cards, one for each protocol.
// Each card navigates to a dedicated page with its own BLoC instance.
// BLoCs are created fresh on each navigation push and closed on pop.

import 'package:flutter/material.dart';

import '../../core/di/injection.dart';
import '../bloc/socket_bloc.dart';
import 'socket_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Socket Demo'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            _ProtocolCard(
              icon:        Icons.wifi,
              title:       'WebSocket',
              subtitle:    'Port 8080  ·  ws:// or wss://',
              description: 'TCP + HTTP Upgrade handshake. Built-in framing, '
                           'opcodes, and masking. Auth via URL query param.',
              accentColor: Colors.indigo,
              tag:         'RFC 6455',
              onTap: () => _openPage(context, 'ws'),
            ),
            const SizedBox(height: 16),
            _ProtocolCard(
              icon:        Icons.cable,
              title:       'Raw TCP Socket',
              subtitle:    'Port 9000  ·  tcp://',
              description: 'Pure TCP stream. Manual length-prefix framing. '
                           'Auth via AUTH message after connect. '
                           'Lower overhead, full protocol control.',
              accentColor: Colors.teal,
              tag:         'dart:io Socket',
              onTap: () => _openPage(context, 'tcp'),
            ),
            const Spacer(),
            _ComparisonTable(),
          ],
        ),
      ),
    );
  }

  void _openPage(BuildContext context, String instanceName) {
    // Create a fresh BLoC for this navigation session.
    // It will be closed automatically when the page is popped
    // because BlocProvider disposes BLoCs it owns.
    final isWs   = instanceName == 'ws';
    final bloc   = sl<SocketBloc>(instanceName: instanceName);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SocketPage(
          bloc:          bloc,
          title:         isWs ? 'WebSocket' : 'Raw TCP Socket',
          protocolLabel: isWs
              ? 'ws://  ·  Port 8080  ·  HTTP Upgrade'
              : 'tcp://  ·  Port 9000  ·  Length-Prefix Framing',
          accentColor: isWs ? Colors.indigo : Colors.teal,
        ),
      ),
    );
  }
}

// ─── Protocol Card ────────────────────────────────────────────────────────────
class _ProtocolCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final String   description;
  final Color    accentColor;
  final String   tag;
  final VoidCallback onTap;

  const _ProtocolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.accentColor,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon badge
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 26),
              ),
              const SizedBox(width: 16),

              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: accentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: accentColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Quick Comparison Table ───────────────────────────────────────────────────
class _ComparisonTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Handshake',    'HTTP Upgrade',         'TCP only'),
      ('Auth',         'URL query param',       'AUTH message'),
      ('Framing',      'Auto (RFC 6455)',       'Manual (4-byte prefix)'),
      ('Heartbeat',    'WS ping/pong frame',    'App-level PING/PONG'),
      ('Overhead',     '2–10 byte/frame',       '4 byte/message'),
      ('ngrok',        'ngrok http (free)',     'ngrok tcp (paid)'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Comparison',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(1.2),
                1: FlexColumnWidth(1.5),
                2: FlexColumnWidth(1.5),
              },
              children: [
                // Header
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  children: [
                    _cell('', isHeader: true),
                    _cell('WebSocket', isHeader: true, color: Colors.indigo),
                    _cell('Raw TCP',   isHeader: true, color: Colors.teal),
                  ],
                ),
                ...rows.map(
                  (r) => TableRow(
                    children: [
                      _cell(r.$1, isLabel: true),
                      _cell(r.$2),
                      _cell(r.$3),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(
    String text, {
    bool isHeader = false,
    bool isLabel  = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Text(
        text,
        style: TextStyle(
          fontSize:   isHeader ? 11 : 10,
          fontWeight: isHeader || isLabel ? FontWeight.bold : FontWeight.normal,
          color:      color ?? (isLabel ? Colors.grey.shade700 : Colors.grey.shade800),
        ),
      ),
    );
  }
}
