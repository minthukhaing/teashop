/// Builds the plain-text / ESC/POS-style payload for a teashop order receipt.
library teashop_pos.printer.receipt_text;

import 'dart:typed_data';

import 'printer_models.dart';

import '../../data/models/order.dart';

/// Returns the ESC/POS payload for an order, ready to be sent to a Bluetooth
/// receipt printer over the serial protocol.
/// See [printer_models.ReceiptBuilder] for the supported escape sequences.
Uint8List buildPayload(Order order) {
  // Delegate to the builder for consistency with the rest of the module.
  return ReceiptBuilder.buildPayload(order);
}

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

String _money(double amount) => '\$${amount.toStringAsFixed(2)}';
