// lib/presentation/widgets/message_log_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/socket_message.dart';
import '../bloc/socket_bloc.dart';
import '../bloc/socket_state.dart';

class MessageLogPanel extends StatefulWidget {
  const MessageLogPanel({super.key});
  @override
  State<MessageLogPanel> createState() => _MessageLogPanelState();
}

class _MessageLogPanelState extends State<MessageLogPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SocketBloc, SocketState>(
      listenWhen: (p, c) => p.messageHistory.length != c.messageHistory.length,
      listener: (_, __) => _scrollToBottom(),
      buildWhen: (p, c) => p.messageHistory != c.messageHistory,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Message Log (${state.messageHistory.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: state.messageHistory.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: state.messageHistory.length,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4,
                      ),
                      itemBuilder: (context, index) {
                        final msg = state.messageHistory[index];
                        return _MessageTile(message: msg);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MessageTile extends StatelessWidget {
  final SocketMessage message;
  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = _typeDisplay(message.type);
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestamp);
    final timeStr =
        '${time.hour.toString().padLeft(2,'0')}:'
        '${time.minute.toString().padLeft(2,'0')}:'
        '${time.second.toString().padLeft(2,'0')}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    if (message.command != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          message.command!,
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: color,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        fontSize: 10, color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                if (message.errorMessage != null)
                  Text(
                    message.errorMessage!,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                if (message.data != null)
                  Text(
                    'items: ${(message.data!['items'] as List?)?.length ?? 0}  '
                    'matched: ${(message.data!['matched'] as List?)?.join(', ') ?? '-'}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData, String) _typeDisplay(MessageType type) {
    switch (type) {
      case MessageType.command:       return (Colors.blue,   Icons.send,          'COMMAND →');
      case MessageType.dataResponse:  return (Colors.green,  Icons.download_done, 'DATA ←');
      case MessageType.connectionAck: return (Colors.teal,   Icons.verified,      'ACK ←');
      case MessageType.error:         return (Colors.red,    Icons.error_outline,  'ERROR ←');
      case MessageType.auth:          return (Colors.purple, Icons.lock,           'AUTH →');
      case MessageType.ping:          return (Colors.grey,   Icons.favorite_border,'PING →');
      case MessageType.pong:          return (Colors.grey,   Icons.favorite,       'PONG ←');
      case MessageType.unknown:       return (Colors.grey,   Icons.help_outline,   'UNKNOWN');
    }
  }
}
