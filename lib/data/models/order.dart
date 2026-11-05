library teashop_pos.data.models.order;

import 'package:json_annotation/json_annotation.dart';

import 'date_time_converter.dart';
import '../../core/constants/app_constants.dart';
import 'order_item.dart';

part 'order.g.dart';

/// A customer order placed at a table, with its line items.
@JsonSerializable(explicitToJson: true)
class Order {
  static const String statusPending = 'pending';

  Order({
    this.id,
    required this.tableNumber,
    this.status = statusPending,
    required this.total,
    this.customerName,
    this.notes,
    this.createdAt,
    this.items = const [],
  });

  final int? id;
  final String tableNumber;
  final String status;
  final double total;
  final String? customerName;
  final String? notes;

  @IsoDateTimeConverter()
  final DateTime? createdAt;

  final List<OrderItem> items;

  /// Column-friendly map for SQLite (snake_case keys), without nested items.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'table_number': tableNumber,
      'status': status,
      'total': total,
      'customer_name': customerName,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Order.fromMap(Map<String, Object?> map) {
    return Order(
      id: map['id'] as int?,
      tableNumber: map['table_number'] as String,
      status: map['status'] as String,
      total: (map['total'] as num).toDouble(),
      customerName: map['customer_name'] as String?,
      notes: map['notes'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
  Map<String, dynamic> toJson() => _$OrderToJson(this);

  /// Total quantity of all line items.
  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  Order copyWith({
    int? id,
    String? tableNumber,
    String? status,
    double? total,
    String? customerName,
    String? notes,
    DateTime? createdAt,
    bool clearCreatedAt = false,
    List<OrderItem>? items,
  }) {
    return Order(
      id: id ?? this.id,
      tableNumber: tableNumber ?? this.tableNumber,
      status: status ?? this.status,
      total: total ?? this.total,
      customerName: customerName ?? this.customerName,
      notes: notes ?? this.notes,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  @override
  String toString() => 'Order(id: $id, table: $tableNumber, total: $total)';
}

