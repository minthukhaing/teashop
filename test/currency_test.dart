import 'package:flutter_test/flutter_test.dart';

import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/data/models/order.dart';
import 'package:teashop_pos/data/models/order_item.dart';
import 'package:teashop_pos/presentation/app_theme.dart';
import 'package:teashop_pos/printer/receipt_text.dart';

void main() {
  test('all money output uses the canonical Kyat unit', () {
    expect(AppConstants.currency, 'ကျပ်');
    expect(formatKyat(1500), '1,500 ${AppConstants.currency}');
    expect(formatMoney(95), '95 ${AppConstants.currency}');
  });

  test('receipts print prices and totals with the Kyat unit', () {
    final receipt = formatOrder(Order(
      id: 1,
      tableNumber: 'T1',
      total: 1500,
      items: [
        OrderItem(name: 'Chai', price: 1500, quantity: 1),
      ],
    ));
    expect(receipt, contains('1500 ${AppConstants.currency}'));
    expect(receipt, contains('TOTAL: 1500 ${AppConstants.currency}'));
  });
}
