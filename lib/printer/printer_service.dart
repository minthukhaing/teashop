/// Abstraction for a hardware receipt printer.
///
/// The waiter and kitchen screens drive the printer through this interface,
/// so a different implementation (e.g. a different Bluetooth library or a
/// USB/CI printer) can be swapped in without touching the UI.
library teashop_pos.printer.service;

import 'dart:typed_data';

import 'printer_models.dart';

/// Result of a device scan.
class ScanResult {
  ScanResult({required this.devices, required this.hasPending, this.error});
  final List<BluetoothDevice> devices;
  final bool hasPending; // true when the last scan returned none yet
  final String? error;
}

/// A connected Bluetooth printer and its current state.
enum PrinterState { idle, connecting, connected, disconnected, error }

/// Central service for discovering and printing to a Bluetooth receipt printer.
///
/// State machine:
///   idle -> scanning -> connected -> idle
///   connected -> disconnected
abstract class PrinterService {
  /// The current state of the printer.
  PrinterState get state;

  /// Whether a scanner result with pending additions is available.
  bool get hasPending;

  /// Convenience flag: true when [state] is [PrinterState.connected].
  bool get isConnected;

  /// Whether a Bluetooth stack is available on this platform.
  Future<bool> get isAvailable;

  /// Requests the platform to start scanning for Bluetooth devices.
  /// Returns a [ScanResult]. Call repeatedly until [hasPending] is true.
  Future<ScanResult> scanDevices();

  /// Connects to the device with [address].
  /// Does NOT enable notifications automatically (the printer's GATT layer is
  /// highly non-standard); this is intentionally a plain connection.
  Future<void> connect(String address);

  /// Disconnects from the currently connected printer.
  Future<void> disconnect();

  /// Sends raw bytes to the printer.
  /// Returns the number of bytes written.
  Future<int> write(Uint8List data);

  /// Closes the service and releases platform resources.
  Future<void> dispose();
}