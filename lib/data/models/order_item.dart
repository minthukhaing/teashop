library teashop_pos.data.models.order_item;

import 'package:json_annotation/json_annotation.dart';

import '../../core/utils/myanmar_text.dart';

part 'order_item.g.dart';

/// One line within an order (a menu item with quantity and customizations).
@JsonSerializable()
class OrderItem {
  OrderItem({
    this.id,
    this.orderId,
    this.menuItemId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.notes,
    this.customizations,
  });

  final int? id;
  final int? orderId;
  final int? menuItemId;
  final String name;
  final double price;
  final int quantity;
  final String? notes;            // e.g. "extra hot, less sugar"
  final String? customizations;   // free-form customization text

  /// Column-friendly map for SQLite (snake_case keys).
  ///
  /// Free-text fields are normalised to Unicode **NFC** (see [MyanmarText]).
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'order_id': orderId,
      'menu_item_id': menuItemId,
      'name': MyanmarText.normalize(name),
      'price': price,
      'quantity': quantity,
      'notes': MyanmarText.normalizeNullable(notes),
      'customizations': MyanmarText.normalizeNullable(customizations),
    };
  }

  factory OrderItem.fromMap(Map<String, Object?> map) {
    return OrderItem(
      id: map['id'] as int?,
      orderId: map['order_id'] as int?,
      menuItemId: map['menu_item_id'] as int?,
      name: MyanmarText.normalize(map['name'] as String),
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
      notes: MyanmarText.normalizeNullable(map['notes'] as String?),
      customizations:
          MyanmarText.normalizeNullable(map['customizations'] as String?),
    );
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) => _$OrderItemFromJson(json);
  Map<String, dynamic> toJson() => _$OrderItemToJson(this);

  /// Line subtotal = price × quantity.
  double get subtotal => price * quantity;

  OrderItem copyWith({
    int? id,
    int? orderId,
    int? menuItemId,
    String? name,
    double? price,
    int? quantity,
    String? notes,
    String? customizations,
  }) {
    return OrderItem(
      id: id ?? this.id,
      orderId: orderId ?? this.orderId,
      menuItemId: menuItemId ?? this.menuItemId,
      name: name ?? this.name,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      notes: notes ?? this.notes,
      customizations: customizations ?? this.customizations,
    );
  }

  @override
  String toString() => 'OrderItem(name: $name, qty: $quantity)';
}
