library teashop_pos.presentation.admin.screens.admin_unpaid_tables_screen;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/order.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../voucher_screen.dart';

/// Real-time state holder for the Admin "Unpaid Tables" dashboard.
///
/// The Admin app hosts the local POS server in-process and shares the very
/// same SQLite database that the HTTP handlers (`/api/orders`) write to.
/// Polling [AppDatabase.getOrders] with `unpaidOnly: true` therefore gives a
/// live view of everything the waiters do - new orders, edits and checkouts
/// all appear here within one poll interval without any extra server work.
class UnpaidOrdersNotifier extends ChangeNotifier {
  UnpaidOrdersNotifier(this._db);
  final AppDatabase _db;

  List<Order> _orders = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastPoll;
  Timer? _timer;
  bool _disposed = false;

  List<Order> get orders => _orders;
  bool get loading => _loading;
  String? get error => _error;
  DateTime? get lastPoll => _lastPoll;

  /// Orders that are still open bills (pending/preparing/ready) - they stay
  /// in this list until checkout marks them `paid`.
  int get unpaidCount => _orders.length;

  /// Number of distinct tables with an open bill.
  int get tableCount => _orders.map((o) => o.tableNumber).toSet().length;

  /// Sum of all open bills, in Kyat.
  double get unpaidTotal => _orders.fold(0.0, (sum, o) => sum + o.total);

  /// Notifies listeners only while the notifier is still alive (poll() is
  /// async and may complete after the owning screen was disposed).
  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  /// Fetches the current unpaid orders from the shared database.
  Future<void> poll() async {
    if (_loading || _disposed) return;
    _loading = true;
    _safeNotify();
    try {
      _error = null;
      _orders = await _db.getOrders(unpaidOnly: true, limit: 200);
      _lastPoll = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _safeNotify();
    }
  }

  /// Marks [orderId] as paid with [paymentMethod] (cash/kpay/wavepay).
  Future<void> checkout(int orderId, String paymentMethod) async {
    await _db.markOrderPaid(orderId, paymentMethod);
    await poll();
  }

  /// Voids the order (status `cancelled`) and refreshes.
  Future<void> cancel(int orderId) async {
    await _db.updateOrderStatus(orderId, AppConstants.statusCancelled);
    await poll();
  }

  void startPolling({Duration interval = AppConstants.ordersPollInterval}) {
    if (_disposed) return;
    stopPolling();
    _timer = Timer.periodic(interval, (_) => poll());
    poll();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    super.dispose();
  }
}

/// Real-time Unpaid Tables dashboard for the Admin role.
///
/// Shows every table/order whose bill is still open (pending/preparing/ready)
/// and updates live as waiters place or modify orders.  Tapping an order
/// opens a detail sheet with the ordered items, totals in Kyat and direct
/// checkout / cancel / voucher actions.
class AdminUnpaidTablesScreen extends StatefulWidget {
  const AdminUnpaidTablesScreen({super.key});

  @override
  State<AdminUnpaidTablesScreen> createState() =>
      _AdminUnpaidTablesScreenState();
}

class _AdminUnpaidTablesScreenState extends State<AdminUnpaidTablesScreen> {
  late final UnpaidOrdersNotifier _notifier;
  final DateFormat _time = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _notifier = UnpaidOrdersNotifier(AppDatabase.instance);
    _notifier.addListener(_onDataChanged);
    _notifier.startPolling();
  }

  @override
  void dispose() {
    _notifier.removeListener(_onDataChanged);
    _notifier.dispose();
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() => _notifier.poll();

  /// Opens the order detail sheet (items, Kyat totals, actions).
  Future<void> _openDetail(Order order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OrderDetailSheet(
        order: order,
        notifier: _notifier,
        onVoucher: () => _openVoucher(order),
      ),
    );
  }

  Future<void> _openVoucher(Order order) async {
    final settings = await AppDatabase.instance.getShopSettings();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => VoucherScreen(order: order, settings: settings),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final orders = _notifier.orders;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AdminColors.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _liveHeader(),
          if (_notifier.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                'Sync error: ${_notifier.error}',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          Expanded(
            child: _notifier.loading && orders.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_outlined,
                                    size: 64, color: AppColors.success),
                                SizedBox(height: 16),
                                Text('မှာယူမှုအားလုံး ရှင်းပြီးပါပြီ',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 16)),
                                Text('All tables are paid / cleared.',
                                    style: TextStyle(
                                        color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _orderCard(orders[i]),
                      ),
          ),
        ],
      ),
    );
  }

  /// Live status strip: live dot, unpaid counts and Kyat total.
  Widget _liveHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.circle, size: 10, color: AppColors.success),
              const SizedBox(width: 6),
              const Text('LIVE',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success)),
              const Spacer(),
              Text(
                _notifier.lastPoll != null
                    ? 'Updated ${_time.format(_notifier.lastPoll!)}'
                    : 'Loading...',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _summaryChip(
                icon: Icons.table_restaurant,
                label: '${_notifier.tableCount} tables',
              ),
              const SizedBox(width: 8),
              _summaryChip(
                icon: Icons.receipt_long_outlined,
                label: '${_notifier.unpaidCount} bills',
              ),
              const SizedBox(width: 8),
              _summaryChip(
                icon: Icons.account_balance_wallet_outlined,
                label: formatKyat(_notifier.unpaidTotal),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AdminColors.sidebarBg.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AdminColors.sidebarBg),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// One unpaid order card.  Stays in the list until checkout completes.
  Widget _orderCard(Order order) {
    final age = order.createdAt != null
        ? DateTime.now().difference(order.createdAt!)
        : null;
    final ageLabel = age == null
        ? ''
        : age.inMinutes >= 60
            ? '${age.inHours}h ${age.inMinutes % 60}m'
            : '${age.inMinutes}m';
    return Card(
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(order),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AdminColors.sidebarBg.withOpacity(0.1),
                child: Text(
                    'T${order.tableNumber.replaceAll(RegExp(r'[^0-9]'), '')}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Table ${order.tableNumber}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15)),
                    Text(
                      '${order.itemCount} items - $ageLabel',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatKyat(order.total),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success)),
                  statusChip(order.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet shown when the admin taps an unpaid order: full item list,
/// totals in Kyat and direct checkout / cancel / voucher actions.
class _OrderDetailSheet extends StatefulWidget {
  const _OrderDetailSheet({
    required this.order,
    required this.notifier,
    required this.onVoucher,
  });

  final Order order;
  final UnpaidOrdersNotifier notifier;
  final VoidCallback onVoucher;

  @override
  State<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<_OrderDetailSheet> {
  bool _busy = false;

  Future<void> _checkout() async {
    final method = await showDialog<String>(
      context: context,
      builder: (_) => _PaymentDialog(total: widget.order.total),
    );
    if (method == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.notifier.checkout(widget.order.id!, method);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Table ${widget.order.tableNumber} paid via ${_PaymentDialog.labelFor(method)}'),
        backgroundColor: AppColors.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Checkout failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel order?'),
        content: Text(
            'Table ${widget.order.tableNumber} - ${formatKyat(widget.order.total)} will be voided.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.notifier.cancel(widget.order.id!);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Cancel failed: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Table ${order.tableNumber}',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('#${order.id} - ${order.itemCount} items',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
              statusChip(order.status),
            ],
          ),
          const Divider(height: 24),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in order.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('${item.name} x${item.quantity}')),
                          Text(formatKyat(item.price * item.quantity),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              const Spacer(),
              const Text('Total  ',
                  style: TextStyle(color: AppColors.muted)),
              Text(formatKyat(order.total),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AdminColors.sidebarBg,
                    side: BorderSide(
                        color: AdminColors.sidebarBg.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : widget.onVoucher,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('Voucher'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : _cancel,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _busy ? null : _checkout,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.payments_outlined, size: 16),
                  label: Text('Checkout ${AppConstants.currency}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Payment-method picker with cash received / change calculation.
/// Returns the chosen method slug ('cash' / 'kpay' / 'wavepay'), or null.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  final double total;

  static const List<({String slug, String label, IconData icon})> methods = [
    (slug: 'cash', label: 'ငွေသား Cash', icon: Icons.payments_outlined),
    (slug: 'kpay', label: 'KPay', icon: Icons.phone_android_outlined),
    (slug: 'wavepay', label: 'WavePay', icon: Icons.waves_outlined),
  ];

  static String labelFor(String slug) =>
      methods.firstWhere((m) => m.slug == slug, orElse: () => methods.first)
          .label;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String _method = 'cash';
  final TextEditingController _cashCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _cashCtrl.dispose();
    super.dispose();
  }

  double? get _received {
    final text = _cashCtrl.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  double get _change => (_received ?? 0) - widget.total;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Checkout - ${formatKyat(widget.total)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in _PaymentDialog.methods)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _method = m.slug),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _method == m.slug
                          ? AppColors.success.withOpacity(0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _method == m.slug
                            ? AppColors.success
                            : AppColors.muted.withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(m.icon,
                            size: 18,
                            color: _method == m.slug
                                ? AppColors.success
                                : AppColors.muted),
                        const SizedBox(width: 8),
                        Text(m.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
            if (_method == 'cash') ...[
              const SizedBox(height: 4),
              TextField(
                controller: _cashCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ငွေလက်ခံ Received (${AppConstants.currency})',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_received != null && _change < 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Received is less than the total.',
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12),
                  ),
                ),
              if (_received != null && _change >= 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'ပြန်အမ်း Change: ${formatKyat(_change)}',
                    style: const TextStyle(
                        color: AppColors.success,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style:
                        const TextStyle(color: AppColors.error, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            if (_method == 'cash' &&
                (_received == null || _received! < widget.total)) {
              setState(() => _error =
                  'Enter the received cash amount (must cover the total).');
              return;
            }
            Navigator.pop(context, _method);
          },
          child: const Text('Confirm Payment'),
        ),
      ],
    );
  }
}
