library teashop_pos.presentation.admin.admin_dashboard;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/order.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final AppDatabase _db = AppDatabase.instance;
  final DateFormat _time = DateFormat.Hm();

  OrderStats? _stats;
  List<Order> _recent = [];
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
      final recent = await _db.getOrders(limit: 12);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _recent = recent;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: GradientBackground(
        child: _loading && _stats == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  sectionTitle(context, 'Overview'),
                  const SizedBox(height: 12),
                  _metrics(context),
                  const SizedBox(height: 24),
                  sectionTitle(context, 'Recent Orders'),
                  const SizedBox(height: 8),
                  if (_recent.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No orders yet.')),
                    )
                  else
                    ResponsiveGrid(
                      compact: 1,
                      medium: 2,
                      expanded: 3,
                      large: 3,
                      childAspectRatio: 2.4,
                      shrinkWrap: true,
                      itemCount: _recent.length,
                      itemBuilder: (context, i) => _orderCard(_recent[i]),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _metrics(BuildContext context) {
    final s = _stats;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = gridColumnsForWidth(
          constraints.maxWidth,
          compact: 2,
          medium: 3,
          expanded: 4,
          large: 4,
        );
        final items = <_Metric>[
          _Metric('Total Orders', '${s?.totalOrders ?? 0}', AppColors.primary),
          _Metric('Pending', '${s?.pendingCount ?? 0}', AppColors.warning),
          _Metric('Preparing', '${s?.preparingCount ?? 0}', AppColors.accent),
          _Metric("Today's Revenue", formatMoney(s?.todayRevenue ?? 0),
              AppColors.success),
        ];
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: items.map(_metricCard).toList(),
        );
      },
    );
  }

  Widget _metricCard(_Metric m) {
    return GlassCard(
      tint: m.color,
      opacity: 0.10,
      elevation: 6,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(m.title,
              style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(m.value,
              style: TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold, color: m.color)),
        ],
      ),
    );
  }

  Widget _orderCard(Order order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text('#${order.id}',
                      style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Table ${order.tableNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(
                        '${order.createdAt != null ? _time.format(order.createdAt!) : "--:--"}  •  ${order.itemCount} items',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                statusChip(order.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(formatMoney(order.total),
                    style: const TextStyle(fontWeight: FontWeight.bold))
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric {
  const _Metric(this.title, this.value, this.color);
  final String title;
  final String value;
  final Color color;
}
