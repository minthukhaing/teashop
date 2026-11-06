library teashop_pos.data.models.menu_item;

import 'package:json_annotation/json_annotation.dart';

import '../../core/utils/myanmar_text.dart';
import 'date_time_converter.dart';

part 'menu_item.g.dart';

/// A sellable menu item (e.g. "Masala Chai", "Veg Sandwich").
@JsonSerializable()
class MenuItem {
  MenuItem({
    this.id,
    required this.name,
    this.description,
    required this.price,
    required this.category,
    this.available = true,
    this.imageUrl,
    this.createdAt,
  });

  final int? id;
  final String name;
  final String? description;
  final double price;
  final String category;
  final bool available;
  final String? imageUrl;

  @IsoDateTimeConverter()
  final DateTime? createdAt;

  /// Column-friendly map for SQLite (snake_case keys).
  ///
  /// All free-text fields are normalised to Unicode **NFC** so the database
  /// stores one canonical form – required for correct Myanmar rendering
  /// (Asat/Virama stacking) and reliable `LIKE` searches.
  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': MyanmarText.normalize(name),
      'description': MyanmarText.normalizeNullable(description),
      'price': price,
      'category': MyanmarText.normalize(category),
      'available': available ? 1 : 0,
      'image_url': imageUrl,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory MenuItem.fromMap(Map<String, Object?> map) {
    return MenuItem(
      id: map['id'] as int?,
      name: MyanmarText.normalize(map['name'] as String),
      description: MyanmarText.normalizeNullable(map['description'] as String?),
      price: (map['price'] as num).toDouble(),
      category: MyanmarText.normalize(map['category'] as String),
      available: (map['available'] as int?)?.toInt() == 1,
      imageUrl: map['image_url'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  factory MenuItem.fromJson(Map<String, dynamic> json) => _$MenuItemFromJson(json);
  Map<String, dynamic> toJson() => _$MenuItemToJson(this);

  MenuItem copyWith({
    int? id,
    String? name,
    String? description,
    double? price,
    String? category,
    bool? available,
    String? imageUrl,
    DateTime? createdAt,
    bool clearCreatedAt = false,
  }) {
    return MenuItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      available: available ?? this.available,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'MenuItem(id: $id, name: $name, price: $price)';
}
