// lib/presentation/widgets/data_items_list.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/socket_bloc.dart';
import '../bloc/socket_state.dart';

class DataItemsList extends StatelessWidget {
  const DataItemsList({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SocketBloc, SocketState>(
      buildWhen: (p, c) => p.receivedItems != c.receivedItems,
      builder: (context, state) {
        if (state.receivedItems.isEmpty) {
          return const Center(
            child: Text(
              'No data yet.\nSend a command to receive data from server.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Received Data (${state.receivedItems.length} items)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: state.receivedItems.length,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemBuilder: (context, index) {
                  final item = state.receivedItems[index];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text(item.id)),
                      title: Text(item.name),
                      subtitle: Text(
                        item.description ?? item.category,
                      ),
                      trailing: Chip(
                        label: Text('${item.value}'),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
