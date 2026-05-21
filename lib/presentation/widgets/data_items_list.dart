// lib/presentation/widgets/data_items_list.dart
//
// Menampilkan list DataItem yang diterima dari server sebagai respons command.
//
// Widget ini di-rebuild otomatis oleh BlocBuilder setiap kali
// state.receivedItems berubah — memenuhi acceptance criteria:
// "Update data lokal dari client setelah menerima data dari server"

import 'package:flutter/material.dart';
import '../../domain/entities/data_item.dart';

class DataItemsList extends StatelessWidget {
  final List<DataItem> items;

  const DataItemsList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'No data received yet.\nSend a command to fetch data.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: items.map((item) => _DataItemCard(item: item)).toList(),
    );
  }
}

// ─── Card untuk satu DataItem ─────────────────────────────────────────────────
class _DataItemCard extends StatelessWidget {
  final DataItem item;
  const _DataItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            item.id,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('Category: ${item.category}'),
        trailing: Chip(
          label: Text('${item.value}'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        ),
      ),
    );
  }
}