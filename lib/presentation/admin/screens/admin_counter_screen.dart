library teashop_pos.presentation.admin.screens.admin_counter_screen;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/order.dart';
import 'package:intl/intl.dart';

/// Counter screen – shows active orders that can be served / cancelled.
class AdminCounterScreen extends StatefulWidget {
  const AdminCounterScreen({super.key});

  @override
  State<AdminCounterScreen> createState() => _AdminCounterScreenState();
}

class _AdminCounterScreenState extends State<AdminCounterScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<Order> _orders = [];
  bool _loading = false;
  final DateFormat _fmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orders = await _db.getOrders(limit: 50);
      if (!mounted) return;
      setState(() {
        _orders = orders.where((o) =>
          o.status == 'pending' || o.status == 'preparing' || o.status == 'ready'
        ).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(Order order, String newStatus) async {
    await _db.updateOrderStatus(order.id!, newStatus);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.sidebarBg,
      child: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.computer, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('မှာယူမှုများ မရှိသေးပါ',
                              style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _orderTile(_orders[i]),
                ),
    );
  }

  Widget _orderTile(Order order) {
    final statusColor = switch (order.status) {
      'pending' => AppColors.warning,
      'preparing' => AppColors.accent,
      'ready' => AppColors.success,
      _ => AppColors.muted,
    };
    final statusLabel = switch (order.status) {
      'pending' => 'စောင့်ဆိုင်း',
      'preparing' => 'ချက်နေ',
      'ready' => 'အဆင်သင့်',
      _ => order.status,
    };
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AdminColors.sidebarBg,
                  child: Text(
                    'T${order.tableNumber}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('စားပွဲ ${order.tableNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${order.createdAt != null ? _fmt.format(order.createdAt!) : "--:--"}  •  ${order.itemCount} items  •  ${formatMoney(order.total)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.5)),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (order.status != 'ready')
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: BorderSide(color: AppColors.success.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Ready', style: TextStyle(fontSize: 13)),
                    onPressed: () => _updateStatus(order, 'ready'),
                  ),
                const SizedBox(width: 8),
                if (order.status == 'ready')
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AdminColors.sidebarBg,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.done_all, size: 16),
                    label: const Text('Served', style: TextStyle(fontSize: 13)),
                    onPressed: () => _updateStatus(order, 'served'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Cancel', style: TextStyle(fontSize: 13)),
                  onPressed: () => _updateStatus(order, 'cancelled'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

