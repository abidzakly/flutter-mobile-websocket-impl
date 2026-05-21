// lib/domain/entities/data_item.dart
//
// Entity yang merepresentasikan satu item data yang diterima dari server.
// Ini adalah "business object" — tidak mengetahui cara serialisasinya.

import 'package:equatable/equatable.dart';

/// [DataItem] — representasi data yang dikirim server sebagai respons command.
///
/// Contoh: server kirim Data A saat client mengirim command "001"
class DataItem extends Equatable {
  final String id;
  final String name;
  final int value;
  final String category;

  const DataItem({
    required this.id,
    required this.name,
    required this.value,
    required this.category,
  });

  @override
  List<Object?> get props => [id, name, value, category];
}