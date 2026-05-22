// lib/domain/entities/data_item.dart

import 'package:equatable/equatable.dart';

class DataItem extends Equatable {
  final String id;
  final String name;
  final int value;
  final String category;
  final String? description;

  const DataItem({
    required this.id,
    required this.name,
    required this.value,
    required this.category,
    this.description,
  });

  @override
  List<Object?> get props => [id, name, value, category, description];
}
