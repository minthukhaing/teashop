// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'order.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Order _$OrderFromJson(Map<String, dynamic> json) => Order(
  id: (json['id'] as num?)?.toInt(),
  tableNumber: json['tableNumber'] as String,
  status: json['status'] as String? ?? AppConstants.statusPending,
  total: (json['total'] as num).toDouble(),
  customerName: json['customerName'] as String?,
  notes: json['notes'] as String?,
  createdAt: const IsoDateTimeConverter().fromJson(
    json['createdAt'] as String?,
  ),
  items:
      (json['items'] as List<dynamic>?)
          ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$OrderToJson(Order instance) => <String, dynamic>{
  'id': instance.id,
  'tableNumber': instance.tableNumber,
  'status': instance.status,
  'total': instance.total,
  'customerName': instance.customerName,
  'notes': instance.notes,
  'createdAt': const IsoDateTimeConverter().toJson(instance.createdAt),
  'items': instance.items.map((e) => e.toJson()).toList(),
};
