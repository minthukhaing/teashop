// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'menu_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MenuItem _$MenuItemFromJson(Map<String, dynamic> json) => MenuItem(
  id: (json['id'] as num?)?.toInt(),
  name: json['name'] as String,
  description: json['description'] as String?,
  price: (json['price'] as num).toDouble(),
  category: json['category'] as String,
  available: json['available'] as bool? ?? true,
  imageUrl: json['imageUrl'] as String?,
  createdAt: const IsoDateTimeConverter().fromJson(
    json['createdAt'] as String?,
  ),
);

Map<String, dynamic> _$MenuItemToJson(MenuItem instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'price': instance.price,
  'category': instance.category,
  'available': instance.available,
  'imageUrl': instance.imageUrl,
  'createdAt': const IsoDateTimeConverter().toJson(instance.createdAt),
};
