/// Builds the plain-text / ESC/POS-style payload for a teashop order receipt.
library teashop_pos.printer.receipt_text;

import 'dart:typed_data';

import 'printer_models.dart';

import '../core/constants/app_constants.dart';
import '../../data/models/order.dart';
import '../../data/models/shop_settings.dart';

/// Returns the ESC/POS payload for an order, ready to be sent to a Bluetooth
/// receipt printer over the serial protocol.
/// See [printer_models.ReceiptBuilder] for the supported escape sequences.
Uint8List buildPayload(Order order) {
  // Delegate to the builder for consistency with the rest of the module.
  return ReceiptBuilder.buildPayload(order);
}

/// Builds the ESC/POS payload for a full POS voucher/bill:
/// shop header, table, date/time, waiter, line items, sub-total,
/// Gov Tax % and grand total.
Uint8List buildVoucherPayload(Order order, ShopSettings settings) {
  ReceiptBuilder.begin();

  // ── Shop header ──────────────────────────────────────────────────────────
  ReceiptBuilder.addHeading(settings.shopName);
  if (settings.shopAddress.isNotEmpty) {
    ReceiptBuilder.addRow('Addr', settings.shopAddress);
  }
  ReceiptBuilder.addSeparator();

  // ── Transaction info ─────────────────────────────────────────────────────
  ReceiptBuilder.addRow('Voucher #', order.id?.toString() ?? '-');
  ReceiptBuilder.addRow('Table', order.tableNumber);
  final created = order.createdAt;
  if (created != null) {
    ReceiptBuilder.addRow(
        'Date', '${created.year}-${_two(created.month)}-${_two(created.day)}');
    ReceiptBuilder.addRow(
        'Time', '${_two(created.hour)}:${_two(created.minute)}');
  }
  final waiter = order.waiterName;
  if (waiter != null && waiter.isNotEmpty) {
    ReceiptBuilder.addRow('Waiter', waiter);
  }
  ReceiptBuilder.addSeparator();

  // ── Line items ───────────────────────────────────────────────────────────
  ReceiptBuilder.addHeading('Items');
  for (final item in order.items) {
    ReceiptBuilder.addRow('${item.name} x${item.quantity}',
        '${item.subtotal.toStringAsFixed(0)} ${AppConstants.currency}');
  }
  ReceiptBuilder.addSeparator();

  // ── Totals ───────────────────────────────────────────────────────────────
  final subTotal = order.total;
  final tax = settings.taxFor(subTotal);
  ReceiptBuilder.addAmount('Sub-Total', subTotal);
  ReceiptBuilder.addRow('Gov Tax', '${settings.govTaxPercent.toStringAsFixed(1)}%');
  ReceiptBuilder.addAmount('Tax Amount', tax);
  ReceiptBuilder.addHeading('Grand Total');
  ReceiptBuilder.addAmount('TOTAL', settings.grandTotal(subTotal));
  ReceiptBuilder.addBlank();
  ReceiptBuilder.addText('Thank you! Please come again.');
  ReceiptBuilder.addBlank();
  ReceiptBuilder.addBlank();
  ReceiptBuilder.addCut();

  return ReceiptBuilder.serialize();
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Standalone helper for callers that do not want to go through the
/// [ReceiptBuilder] state machine.
String formatOrder(Order order) {
  final sb = StringBuffer();

  sb.writeln('TEASHOP RECEIPT');
  sb.writeln('Table: ${order.tableNumber}');
  if (order.customerName != null && order.customerName!.isNotEmpty) {
    sb.writeln('Customer: ${order.customerName}');
  }
  if (order.notes != null && order.notes!.isNotEmpty) {
    sb.writeln('Notes: ${order.notes}');
  }
  sb.writeln();
  sb.writeln('ORDER');
  for (final item in order.items) {
    sb.writeln('${item.name}  x${item.quantity}  ${_money(item.subtotal)}');
  }
  sb.writeln();
  sb.writeln('TOTAL: ${_money(order.total)}');
  sb.writeln();
  sb.writeln('[CUT]'); // represents form feed

  return sb.toString();
}

String _money(double amount) =>
    '${amount.toStringAsFixed(0)} ${AppConstants.currency}';
