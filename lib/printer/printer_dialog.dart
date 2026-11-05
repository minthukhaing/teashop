/// Guided Bluetooth receipt-printer workflow.
///
/// Walks the operator through: scan -> pick -> confirm -> print.
library teashop_pos.printer.dialog;

import 'package:flutter/material.dart';

import 'printer_models.dart';
import 'printer_service.dart';
import 'receipt_printer_service.dart';

import '../../data/models/order.dart';

class PrinterDialog extends StatefulWidget {
  const PrinterDialog({
    super.key,
    required this.printer,
    required this.order,
  });

  final PrinterService printer;
  final Order order;

  @override
  State<PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<PrinterDialog> {
  PrinterState _state = PrinterState.idle;
  String? _error;
  List<BluetoothDevice> _devices = const [];
  BluetoothDevice? _selectedDevice;
  bool _scanning = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    _state = widget.printer.isConnected ? PrinterState.connected : PrinterState.idle;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final available = await widget.printer.isAvailable;
    if (!mounted) return;

    if (available && widget.printer.isConnected) {
      setState(() {
        _state = PrinterState.connected;
        _selectedDevice = _deviceFor(widget.printer);
      });
      return;
    }

    await _scan();
  }

  Future<void> _scan() async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _error = null;
    });

    final result = await widget.printer.scanDevices();
    if (!mounted) return;
    setState(() {
      _devices = result.devices;
      _scanning = false;
      _error = result.error;
      if (result.hasPending && result.devices.isNotEmpty) {
        _selectedDevice = result.devices.first;
      }
    });
  }

  BluetoothDevice _deviceFor(PrinterService printer) {
    return _devices.firstWhere(
      (d) => _selectedDevice != null && d.address == _selectedDevice!.address,
      orElse: () => _devices.first,
    );
  }

  Future<void> _pick(BluetoothDevice device) async {
    if (!mounted) return;
    setState(() {
      _selectedDevice = device;
    });
    try {
      await widget.printer.connect(device.address);
      if (!mounted) return;
      setState(() {
        _state = PrinterState.connected;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _state = PrinterState.error;
      });
    }
  }

  Future<void> _print() async {
    if (!mounted) return;
    setState(() {
      _printing = true;
      _error = null;
    });

    try {
      final receipt = ReceiptPrinter(printer: widget.printer);
      final count = await receipt.printOrder(widget.order);
      if (!mounted) return;
      setState(() {
        _printing = false;
        _state = PrinterState.idle;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Receipt printed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _printing = false;
        _error = e.toString();
        _state = PrinterState.error;
      });
    }
  }

  Widget _buildContent() {
    final children = <Widget>[_statusCard()];
    if (_selectedDevice != null) {
      children.add(
        ListTile(title: Text('Selected: ${_selectedDevice!.name} (${_selectedDevice!.address})')),
      );
    }
    if (_error != null && _state == PrinterState.error) {
      children.add(
        ListTile(
          title: Text(_error!, style: const TextStyle(color: Colors.red)),
          trailing: TextButton(onPressed: _scan, child: const Text('Retry')),
        ),
      );
    }
    if (_scanning) {
      children.add(const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
    }
    if (_devices.isNotEmpty && _state != PrinterState.connected) {
      children.add(
        Column(
          children: [
            const SizedBox(height: 12),
            const Text('Available printers', style: TextStyle(fontWeight: FontWeight.w600)),
            const Divider(),
            ..._devices.map(
              (d) => RadioListTile<BluetoothDevice>(
                value: d,
                groupValue: _selectedDevice,
                onChanged: _scanning ? null : (v) => _pick(v!),
                title: Text(d.name),
                subtitle: Text(d.address),
              ),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _statusCard() {
    Widget body;
    if (_state == PrinterState.idle) {
      body = const ListTile(
        leading: Icon(Icons.bluetooth_disabled, color: Colors.grey),
        title: Text('Bluetooth not connected'),
        subtitle: Text('Tap to scan / connect'),
      );
    } else if (_state == PrinterState.connected) {
      body = ListTile(
        leading: const Icon(Icons.bluetooth_connected, color: Colors.green),
        title: const Text('Printer connected'),
        subtitle: Text(_selectedDevice != null ? _selectedDevice!.name : 'Unknown'),
      );
    } else {
      body = ListTile(
        leading: const Icon(Icons.error, color: Colors.red),
        title: const Text('Connection failed'),
        subtitle: Text(_error ?? 'Unknown error'),
      );
    }
    return Card(child: body);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Print Receipt — Bluetooth Printer'),
      content: _buildContent(),
      actions: [
        FilledButton(
          onPressed: _state == PrinterState.connected && !_printing ? _print : null,
          child: _printing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Print'),
        ),
      ],
    );
  }
}
