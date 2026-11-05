// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OrderItem _$OrderItemFromJson(Map<String, dynamic> json) => OrderItem(
  id: (json['id'] as num?)?.toInt(),
  orderId: (json['orderId'] as num?)?.toInt(),
  menuItemId: (json['menuItemId'] as num?)?.toInt(),
  name: json['name'] as String,
  price: (json['price'] as num).toDouble(),
  quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  notes: json['notes'] as String?,
  customizations: json['customizations'] as String?,
);

Map<String, dynamic> _$OrderItemToJson(OrderItem instance) => <String, dynamic>{
  'id': instance.id,
  'orderId': instance.orderId,
  'menuItemId': instance.menuItemId,
  'name': instance.name,
  'price': instance.price,
  'quantity': instance.quantity,
  'notes': instance.notes,
  'customizations': instance.customizations,
};
