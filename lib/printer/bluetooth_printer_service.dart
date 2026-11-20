/// Concrete [PrinterService] backed by `flutter_bluetooth_serial`.
///
/// Talks to classic Bluetooth (SPP) thermal receipt printers - the kind most
/// cheap 58mm/80mm POS printers use. Only Android supports Bluetooth Classic
/// pairing/SPP; on other platforms [isAvailable] reports `false` so the UI can
/// degrade gracefully.
library teashop_pos.printer.bluetooth_service;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
    as bts;

import 'printer_models.dart';
import 'printer_service.dart';

class BluetoothPrinterService implements PrinterService {
  BluetoothPrinterService._();

  /// Shared singleton so the connection survives across screens/dialogs.
  static final BluetoothPrinterService instance = BluetoothPrinterService._();

  bts.BluetoothConnection? _connection;
  PrinterState _state = PrinterState.idle;

  @override
  PrinterState get state => _state;

  @override
  bool get hasPending => false;

  @override
  bool get isConnected => _state == PrinterState.connected;

  @override
  Future<bool> get isAvailable async {
    try {
      final available =
          await bts.FlutterBluetoothSerial.instance.isAvailable ?? false;
      return available;
    } catch (_) {
      // Platform without a Bluetooth Classic stack (iOS/Windows/etc.).
      return false;
    }
  }

  @override
  Future<ScanResult> scanDevices() async {
    try {
      var enabled =
          await bts.FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!enabled) {
        enabled =
            await bts.FlutterBluetoothSerial.instance.requestEnable() == true;
      }
      if (!enabled) {
        return ScanResult(
          devices: const [],
          hasPending: false,
          error: 'Bluetooth is turned off. Enable it and try again.',
        );
      }

      // Thermal printers are paired (bonded) devices - discovery is not
      // needed, the bond already carries the SPP channel.
      final bonded =
          await bts.FlutterBluetoothSerial.instance.getBondedDevices();
      return ScanResult(
        devices: bonded
            .map((d) => BluetoothDevice(
                  name: (d.name?.isNotEmpty ?? false) ? d.name! : 'Unknown',
                  address: d.address,
                ))
            .toList(),
        hasPending: false,
      );
    } catch (e) {
      return ScanResult(devices: const [], hasPending: false, error: '$e');
    }
  }

  @override
  Future<void> connect(String address) async {
    if (address.isEmpty) {
      throw ArgumentError('Printer address is empty.');
    }
    _state = PrinterState.connecting;
    try {
      _connection = await bts.BluetoothConnection.toAddress(address);
      _state = PrinterState.connected;
      // The printer dropping the link (power off / out of range) surfaces
      // here; keep our state in sync.
      _connection!.input?.listen(
        (data) {},
        onDone: () {
          _connection = null;
          _state = PrinterState.disconnected;
        },
        onError: (_) {
          _connection = null;
          _state = PrinterState.error;
        },
      );
    } catch (e) {
      _connection = null;
      _state = PrinterState.error;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      _connection?.finish();
    } catch (_) {
      // Ignore close errors - the link may already be gone.
    }
    _connection = null;
    _state = PrinterState.idle;
  }

  @override
  Future<int> write(Uint8List data) async {
    final connection = _connection;
    if (connection == null || _state != PrinterState.connected) {
      throw StateError('Printer is not connected.');
    }
    connection.output.add(data);
    await connection.output.allSent;
    return data.length;
  }

  @override
  Future<void> dispose() async {
    await disconnect();
  }
}
