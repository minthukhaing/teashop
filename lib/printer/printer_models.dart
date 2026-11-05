/// Printer-related data models and command helpers.
library teashop_pos.printer.models;

import 'dart:convert';
import 'dart:typed_data';

import '../../data/models/order.dart';

/// A discovered nearby Bluetooth printer device.
class BluetoothDevice {
  BluetoothDevice({required this.name, required this.address, this.connected = false});

  final String name;
  final String address;
  bool connected;

  @override
  String toString() => 'BluetoothDevice($name, $address)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BluetoothDevice &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          address == other.address;

  @override
  int get hashCode => Object.hash(name, address, connected);
}

/// A command to send to the printer.
sealed class PrinterCommand {
  const PrinterCommand();
}

/// A line of text to print.
class PrinterCommandText extends PrinterCommand {
  const PrinterCommandText(this.text);
  final String text;
}

/// Feed a blank line.
class PrinterCommandFeed extends PrinterCommand {
  const PrinterCommandFeed();
}

/// Cut the paper.
class PrinterCommandCut extends PrinterCommand {
  const PrinterCommandCut();
}

/// Set font scale.
class PrinterCommandFontScale extends PrinterCommand {
  const PrinterCommandFontScale(this.scale);
  final int scale;
}

/// Set bold on/off.
class PrinterCommandBold extends PrinterCommand {
  const PrinterCommandBold(this.on);
  final bool on;
}

/// Set underline on/off.
class PrinterCommandUnderline extends PrinterCommand {
  const PrinterCommandUnderline(this.on);
  final bool on;
}

/// Line feed multiple lines.
class PrinterCommandLineFeed extends PrinterCommand {
  const PrinterCommandLineFeed(this.lines);
  final int lines;
}

/// Builds and serializes a receipt into a list of bytes to send to the printer.
class ReceiptBuilder {
  ReceiptBuilder._();

  static final _lines = <PrinterCommand>[];

  static void begin() {
    _lines.clear();
  }

  static void addText(String text) {
    _lines.add(PrinterCommandText(text));
  }

  static void addBlank() {
    _lines.add(const PrinterCommandFeed());
  }

  static void addSeparator() {
    _lines.add(PrinterCommandText('—' * 32));
  }

  static void addHeading(String heading) {
    _lines.add(const PrinterCommandBold(true));
    _lines.add(PrinterCommandText(heading.toUpperCase()));
    _lines.add(const PrinterCommandBold(false));
  }

  static void addRow(String label, String? value) {
    final line = value == null || value.isEmpty ? label : '$label $value';
    _lines.add(PrinterCommandText(line));
  }

  static void addAmount(String label, double amount) {
    _lines.add(PrinterCommandText('$label ${_formatMoney(amount)}'));
  }

  static String _formatMoney(double amount) => '\$${amount.toStringAsFixed(2)}';

  static Uint8List buildPayload(Order order) {
    begin();

    addHeading('TEASHOP RECEIPT');
    addRow('Table', order.tableNumber);
    if (order.customerName != null && order.customerName!.isNotEmpty) {
      addRow('Customer', order.customerName);
    }
    if (order.notes != null && order.notes!.isNotEmpty) {
      addRow('Notes', order.notes);
    }
    addBlank();
    addHeading('Order');
    for (final item in order.items) {
      addRow('${item.name}  x${item.quantity}', _formatMoney(item.subtotal));
    }
    addBlank();
    addHeading('Total');
    addAmount('Total', order.total);
    addBlank();

    _lines.add(const PrinterCommandCut());

    final sb = StringBuffer();
    for (final command in _lines) {
      if (command is PrinterCommandText) {
        sb.write(command.text);
        sb.write('\n');
      } else if (command is PrinterCommandFeed) {
        sb.write('\n');
      } else if (command is PrinterCommandCut) {
        sb.write('\x0C');
      } else if (command is PrinterCommandFontScale) {
        sb.write('\x1B\x33${command.scale + 1}\x00');
      } else if (command is PrinterCommandBold) {
        sb.write('\x1B\x21${command.on ? '1' : '0'}\x00');
      } else if (command is PrinterCommandUnderline) {
        sb.write('\x1B\x2D${command.on ? '1' : '0'}\x00');
      } else if (command is PrinterCommandLineFeed) {
        sb.write('\x1B\x32${command.lines}\x00');
      }
    }

    return Uint8List.fromList(utf8.encode(sb.toString()));
  }
}