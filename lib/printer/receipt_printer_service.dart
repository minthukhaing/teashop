/// Prints a human-readable receipt for a finished order to a
/// [PrinterService].
///
/// This layer is responsible for formatting (the receipt text) so that the
/// Bluetooth plumbing in [BluetoothPrinterService] stays purely about transport.
library teashop_pos.printer.receipt;

import 'dart:typed_data';

import 'printer_models.dart';
import 'printer_service.dart';
import 'receipt_text.dart';

import '../../data/models/order.dart';

/// Formats an [order] into a printer-ready [Uint8List] and writes it out.
class ReceiptPrinter {
  /// The underlying printer transport used to send the payload.
  final PrinterService printer;

  ReceiptPrinter({required this.printer});

  /// Prints the order. Returns the number of bytes transmitted, or throws if
  /// the printer is not connected.
  Future<int> printOrder(Order order) async {
    if (!printer.isConnected) {
      throw StateError('Printer is not connected. Connect a Bluetooth printer '
          'first, then print the receipt.');
    }

    final payload = buildPayload(order);
    return printer.write(payload);
  }
}
