// lib/presentation/widgets/command_button_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/socket_bloc.dart';
import '../bloc/socket_event.dart';
import '../bloc/socket_state.dart';

const _commands = [
  ('001', 'Data A',     'Request Data A only'),
  ('010', 'Data B',     'Request Data B only'),
  ('011', 'Data A+B',   'Request Data A and B'),
  ('100', 'Data C',     'Request Data C only'),
  ('101', 'Data A+C',   'Request Data A and C'),
  ('110', 'Data B+C',   'Request Data B and C'),
  ('111', 'All A+B+C',  'Request all data'),
];

class CommandButtonPanel extends StatelessWidget {
  final Color accentColor;
  const CommandButtonPanel({super.key, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocketBloc, SocketState>(
      buildWhen: (p, c) =>
          p.canSendCommand  != c.canSendCommand  ||
          p.commandStatus   != c.commandStatus   ||
          p.lastSentCommand != c.lastSentCommand,
      builder: (context, state) {
        final isSending = state.commandStatus == CommandStatus.sending;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Send Command',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (isSending) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Awaiting ACK...',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: accentColor),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6, runSpacing: 6,
                children: _commands.map((cmd) {
                  final (code, label, tooltip) = cmd;
                  final isActive = state.lastSentCommand == code && isSending;
                  return Tooltip(
                    message: tooltip,
                    child: FilledButton.tonal(
                      onPressed: state.canSendCommand
                          ? () => context
                              .read<SocketBloc>()
                              .add(SocketCommandSent(code))
                          : null,
                      style: isActive
                          ? FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                            )
                          : FilledButton.styleFrom(
                              backgroundColor: accentColor.withOpacity(0.12),
                              foregroundColor: accentColor,
                            ),
                      child: Text(
                        '$code  $label',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}
