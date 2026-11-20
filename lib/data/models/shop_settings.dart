library teashop_pos.data.models.shop_settings;

import '../../core/utils/myanmar_text.dart';

/// Shop profile + billing settings printed on POS vouchers/bills.
///
/// Stored as a single row (`id = 1`) in the `shop_settings` table on the Admin
/// Host and served to Waiter clients via `GET /api/settings`.
class ShopSettings {
  ShopSettings({
    this.shopName = 'Teashop POS',
    this.shopAddress = '',
    this.govTaxPercent = 0,
    this.updatedAt,
  });

  final String shopName;
  final String shopAddress;

  /// Government tax percentage applied on top of the sub-total, e.g. `5` = 5%.
  final double govTaxPercent;

  final DateTime? updatedAt;

  /// Tax amount for a given [subTotal], rounded to 2 decimal places.
  double taxFor(double subTotal) =>
      double.parse((subTotal * govTaxPercent / 100).toStringAsFixed(2));

  /// Grand total = sub-total + government tax, rounded to 2 decimal places.
  double grandTotal(double subTotal) =>
      double.parse((subTotal + taxFor(subTotal)).toStringAsFixed(2));

  Map<String, Object?> toMap() => {
        'id': 1,
        'shop_name': MyanmarText.normalize(shopName),
        'shop_address': MyanmarText.normalizeNullable(shopAddress),
        'gov_tax_percent': govTaxPercent,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory ShopSettings.fromMap(Map<String, Object?> map) => ShopSettings(
        shopName: MyanmarText.normalize(map['shop_name'] as String? ?? ''),
        shopAddress:
            MyanmarText.normalizeNullable(map['shop_address'] as String?) ??
                '',
        govTaxPercent: (map['gov_tax_percent'] as num?)?.toDouble() ?? 0,
        updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'shopName': shopName,
        'shopAddress': shopAddress,
        'govTaxPercent': govTaxPercent,
      };

  factory ShopSettings.fromJson(Map<String, dynamic> json) => ShopSettings(
        shopName: json['shopName'] as String? ?? 'Teashop POS',
        shopAddress: json['shopAddress'] as String? ?? '',
        govTaxPercent: (json['govTaxPercent'] as num?)?.toDouble() ?? 0,
      );

  ShopSettings copyWith({
    String? shopName,
    String? shopAddress,
    double? govTaxPercent,
  }) =>
      ShopSettings(
        shopName: shopName ?? this.shopName,
        shopAddress: shopAddress ?? this.shopAddress,
        govTaxPercent: govTaxPercent ?? this.govTaxPercent,
        updatedAt: DateTime.now(),
      );
}
