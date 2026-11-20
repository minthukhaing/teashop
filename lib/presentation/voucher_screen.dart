/// POS voucher / bill preview screen.
///
/// Renders a receipt-styled preview of an [Order] using the shop profile in
/// [ShopSettings]: shop name + address, voucher/table/date-time, the waiter
/// who processed the order, line items with quantities and sub-totals, the
/// sub-total, the government tax percentage and the grand total.
///
/// A "Print Voucher" button sends the same content to a Bluetooth thermal
/// printer (Android only) via [BluetoothPrinterService].
library teashop_pos.presentation.voucher_screen;

import 'package:flutter/material.dart';

import '../data/models/order.dart';
import '../data/models/shop_settings.dart';
import '../printer/bluetooth_printer_service.dart';
import '../printer/printer_dialog.dart';
import '../printer/receipt_text.dart';
import 'app_theme.dart';

class VoucherScreen extends StatelessWidget {
  const VoucherScreen({
    super.key,
    required this.order,
    required this.settings,
  });

  final Order order;
  final ShopSettings settings;

  @override
  Widget build(BuildContext context) {
    final subTotal = order.total;
    final taxAmount = settings.taxFor(subTotal);
    final grandTotal = settings.grandTotal(subTotal);
    final created = order.createdAt;

    return Scaffold(
      backgroundColor: AppColors.surfaceCream,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text('Voucher #${order.id ?? '-'}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Shop header ────────────────────────────────────
                        Text(
                          settings.shopName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (settings.shopAddress.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            settings.shopAddress,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const _DashedDivider(),
                        const SizedBox(height: 8),

                        // ── Transaction info ───────────────────────────────
                        _infoRow('Voucher #', '${order.id ?? '-'}'),
                        _infoRow('Table', order.tableNumber),
                        _infoRow(
                          'Date',
                          created != null
                              ? '${created.year}-${_two(created.month)}-${_two(created.day)}'
                              : '-',
                        ),
                        _infoRow(
                          'Time',
                          created != null
                              ? '${_two(created.hour)}:${_two(created.minute)}'
                              : '-',
                        ),
                        _infoRow('Waiter', order.waiterName ?? '-'),
                        const SizedBox(height: 8),
                        const _DashedDivider(),
                        const SizedBox(height: 8),

                        // ── Line items ─────────────────────────────────────
                        const Text(
                          'ITEMS',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        for (final item in order.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.quantity} x ${item.name}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  formatMoney(item.subtotal),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        const _DashedDivider(),
                        const SizedBox(height: 8),

                        // ── Totals ─────────────────────────────────────────
                        _totalRow('Sub-Total', formatMoney(subTotal)),
                        _totalRow(
                            'Gov Tax (${settings.govTaxPercent.toStringAsFixed(1)}%)',
                            formatMoney(taxAmount)),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'GRAND TOTAL',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              Expanded(child: Container()),
                              Text(
                                formatMoney(grandTotal),
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Thank you! Please come again.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Print action ─────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.print),
                  label: const Text('Print Voucher',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  onPressed: () => _printVoucher(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Expanded(child: Container()),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Expanded(child: Container()),
          Text(value, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  /// Sends the voucher payload to the connected Bluetooth printer. When no
  /// printer is connected, offers to open the guided printer setup dialog
  /// first (the operator can then tap "Print Voucher" again).
  Future<void> _printVoucher(BuildContext context) async {
    final printer = BluetoothPrinterService.instance;

    if (!printer.isConnected) {
      final connect = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Printer not connected'),
          content: const Text(
              'Connect a Bluetooth printer first, then tap "Print Voucher" again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
      if (connect == true && context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => PrinterDialog(
            printer: printer,
            order: order,
          ),
        );
      }
      return;
    }

    try {
      final bytes = buildVoucherPayload(order, settings);
      final sent = await printer.write(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voucher sent to printer ($sent bytes).')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }
}

/// Dashed receipt-style divider.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 8).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => const SizedBox(
              width: 4,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.black38),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _two(int n) => n.toString().padLeft(2, '0');

