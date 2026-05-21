// lib/presentation/widgets/message_log_panel.dart
//
// Panel log yang menampilkan history semua pesan yang diterima dari server.
//
// Berguna untuk:
//   - Debugging saat development
//   - Monitoring komunikasi di QA/staging
//   - Referensi visual untuk memahami flow pesan
//
// Menampilkan maks 10 pesan terbaru (terbaru di atas) agar tidak terlalu panjang.

import 'package:flutter/material.dart';
import '../../domain/entities/socket_message.dart';

class MessageLogPanel extends StatelessWidget {
  final List<SocketMessage> messages;

  const MessageLogPanel({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No messages yet.',
          style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
        ),
      );
    }

    // Tampilkan terbaru di atas, batasi 10 entry
    final reversed = messages.reversed.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...reversed.map((msg) => _LogEntry(message: msg)),
        if (messages.length > 10)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '... and ${messages.length - 10} more messages',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

// ─── Satu baris log ───────────────────────────────────────────────────────────
class _LogEntry extends StatelessWidget {
  final SocketMessage message;
  const _LogEntry({required this.message});

  @override
  Widget build(BuildContext context) {
    final time    = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final timeStr = '${_pad(time.hour)}:${_pad(time.minute)}:${_pad(time.second)}';
    final isError = message.type == MessageType.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isError ? Colors.red.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            timeStr,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          const SizedBox(width: 8),
          // Type badge
          _TypeBadge(type: message.type),
          const SizedBox(width: 6),
          // Detail
          Expanded(
            child: Text(
              _buildDetail(message),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isError ? Colors.red.shade700 : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _buildDetail(SocketMessage msg) {
    if (msg.type == MessageType.error) {
      return '${msg.errorCode}: ${msg.errorMessage}';
    }
    final cmdPart = msg.command != null ? ' cmd:${msg.command}' : '';
    final idPart  = msg.requestId.isNotEmpty
        ? ' id:${msg.requestId.substring(0, 8)}...'
        : '';
    return '$cmdPart$idPart';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}

// ─── Badge warna berdasarkan tipe pesan ──────────────────────────────────────
class _TypeBadge extends StatelessWidget {
  final MessageType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (type) {
      MessageType.dataResponse  => ('DATA',  Colors.blue),
      MessageType.connectionAck => ('ACK',   Colors.green),
      MessageType.error         => ('ERR',   Colors.red),
      MessageType.heartbeat     => ('PING',  Colors.grey),
      _                         => ('MSG',   Colors.grey),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}