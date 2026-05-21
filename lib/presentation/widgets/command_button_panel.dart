// lib/presentation/widgets/command_button_panel.dart
//
// Panel tombol command: 001, 011, 111
// Masing-masing tombol mengirim command berbeda ke server.
// Setiap CommandTile menampilkan loading indicator saat command sedang dikirim.

import 'package:flutter/material.dart';

class CommandButtonPanel extends StatelessWidget {
  final bool isEnabled;
  final bool isSending;
  final String? lastCommand;
  final ValueChanged<String> onCommand;

  const CommandButtonPanel({
    super.key,
    required this.isEnabled,
    required this.isSending,
    required this.onCommand,
    this.lastCommand,
  });

  // Definisi semua command yang tersedia.
  // Tambah entry baru di sini untuk menambah command tanpa ubah widget lain.
  static const _commands = [
    _CommandDef('001', 'Get Data A',   'Returns item A only',        Icons.looks_one),
    _CommandDef('011', 'Get A + B',    'Returns items A and B',      Icons.looks_two),
    _CommandDef('111', 'Get All',      'Returns all available data', Icons.all_inclusive),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _commands.map((cmd) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _CommandTile(
          def:       cmd,
          isEnabled: isEnabled,
          isLoading: isSending && lastCommand == cmd.code,
          onTap:     () => onCommand(cmd.code),
        ),
      )).toList(),
    );
  }
}

// ─── Internal tile widget untuk setiap command ────────────────────────────────
class _CommandTile extends StatelessWidget {
  final _CommandDef def;
  final bool isEnabled;
  final bool isLoading;
  final VoidCallback onTap;

  const _CommandTile({
    required this.def,
    required this.isEnabled,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isEnabled
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.grey.shade200,
        child: isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Icon(def.icon, size: 20),
      ),
      title: Text(
        def.label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(def.description),
      trailing: Chip(
        label: Text(
          def.code,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      enabled:  isEnabled && !isLoading,
      onTap:    isEnabled && !isLoading ? onTap : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade200),
      ),
    );
  }
}

// ─── Data class untuk definisi sebuah command ─────────────────────────────────
class _CommandDef {
  final String   code;
  final String   label;
  final String   description;
  final IconData icon;
  const _CommandDef(this.code, this.label, this.description, this.icon);
}
