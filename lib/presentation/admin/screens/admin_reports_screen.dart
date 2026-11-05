library teashop_pos.presentation.admin.screens.admin_reports_screen;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/order.dart';

/// Reports screen – daily/summary sales reports.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  final AppDatabase _db = AppDatabase.instance;
  final DateFormat _dateFmt = DateFormat('dd MMM yyyy');
  final DateFormat _timeFmt = DateFormat('HH:mm');

  OrderStats? _stats;
  List<Order> _orders = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _db.getOrderStats();
      final orders = await _db.getOrders(limit: 100);
      if (!mounted) return;
      final served = orders.where((o) => o.status == 'served').toList();
      setState(() {
        _stats = stats;
        _orders = served;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    return RefreshIndicator(
      onRefresh: _load,
      color: AdminColors.sidebarBg,
      child: _loading && s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'ယနေ့ ${_dateFmt.format(DateTime.now())} အစီရင်ခံစာ',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                // Revenue card
                _revenueCard(s),
                const SizedBox(height: 16),
                // Stats grid
                _statsGrid(s),
                const SizedBox(height: 20),
                const Text('ပြီးစီးသော မှာယူမှုများ',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (_orders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('မှာယူမှု မရှိသေးပါ',
                          style: TextStyle(color: AppColors.muted)),
                    ),
                  )
                else
                  ..._orders.map((o) => _orderRow(o)),
              ],
            ),
    );
  }

  Widget _revenueCard(OrderStats? s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AdminColors.sidebarBg,
            AdminColors.sidebarBg.withOpacity(0.8)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AdminColors.sidebarBg.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Text('ယနေ့ ဝင်ငွေ',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(s?.todayRevenue ?? 0),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'မှာယူမှု ${s?.servedCount ?? 0} ခု ပြီးစီး',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _statsGrid(OrderStats? s) {
    final items = [
      _StatItem('စုစုပေါင်း', s?.totalOrders ?? 0, Icons.list_alt, AppColors.primary),
      _StatItem('ပြီးစီး', s?.servedCount ?? 0, Icons.check_circle, AppColors.success),
      _StatItem('ပယ်ဖျက်', s?.cancelledCount ?? 0, Icons.cancel, AppColors.error),
      _StatItem('ဆဲဆဲ', s?.activeCount ?? 0, Icons.hourglass_empty, AppColors.warning),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.8,
      children: items.map((item) => _statCard(item)).toList(),
    );
  }

  Widget _statCard(_StatItem item) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(item.icon, color: item.color, size: 28),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(item.value.toString(),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: item.color)),
              Text(item.label,
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _orderRow(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AdminColors.sidebarBg.withOpacity(0.1),
            child: Text(
              '#${order.id}',
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AdminColors.sidebarBg),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'စားပွဲ ${order.tableNumber}  •  ${order.itemCount} items',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (order.createdAt != null)
            Text(_timeFmt.format(order.createdAt!),
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(width: 10),
          Text(
            formatMoney(order.total),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

