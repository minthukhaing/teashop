library teashop_pos.presentation.kitchen.kitchen_display;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../app_mode.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';
import 'kds_notifier.dart';

class KitchenDisplayScreen extends StatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  State<KitchenDisplayScreen> createState() => _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends State<KitchenDisplayScreen> {
  final TextEditingController _ipController = TextEditingController();
  late KdsNotifier _notifier;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _ipController.text = AppConfig.instance.adminIp;
    _notifier = KdsNotifier(AppConfig.instance.api);
    _notifier.startPolling();
  }

  @override
  void dispose() {
    _notifier.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _reconnect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    AppConfig.instance.adminIp = ip;
    AppConfig.instance.resetApi();
    _notifier.dispose();
    _notifier = KdsNotifier(AppConfig.instance.api);
    _notifier.startPolling();
    setState(() {});
  }

  List<Order> get _filteredOrders {
    final orders = _notifier.orders;
    if (_filter == 'all') {
      return orders
          .where((o) =>
              o.status != AppConstants.statusServed &&
              o.status != AppConstants.statusCancelled)
          .toList();
    }
    return orders.where((o) => o.status == _filter).toList();
  }

  Future<void> _advance(Order order) async {
    if (order.id == null) return;
    final next = switch (order.status) {
      AppConstants.statusPending => AppConstants.statusPreparing,
      AppConstants.statusPreparing => AppConstants.statusReady,
      AppConstants.statusReady => AppConstants.statusServed,
      _ => order.status,
    };
    await _notifier.setStatus(order.id!, next);
  }

  Future<void> _cancel(Order order) async {
    if (order.id == null) return;
    await _notifier.setStatus(order.id!, AppConstants.statusCancelled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Display'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: AnimatedBuilder(
              animation: _notifier,
              builder: (context, _) => Text(
                _notifier.lastPoll != null
                    ? 'Updated ${DateFormat.Hm().format(_notifier.lastPoll!)}'
                    : 'Connecting…',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
            ),
          ),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            _ipBar(),
            _filterBar(),
            Expanded(
              child: AnimatedBuilder(
                animation: _notifier,
                builder: (context, _) {
                  if (_notifier.loading && _notifier.orders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (_notifier.error != null && _notifier.orders.isEmpty) {
                    return _errorView();
                  }
                  final orders = _filteredOrders;
                  if (orders.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 48, color: AppColors.success),
                          SizedBox(height: 12),
                          Text('All caught up!'),
                        ],
                      ),
                    );
                  }
                  return ResponsiveGrid(
                    compact: 1,
                    medium: 2,
                    expanded: 3,
                    large: 4,
                    padding: const EdgeInsets.all(12),
                    childAspectRatio: 0.75,
                    itemCount: orders.length,
                    itemBuilder: (context, i) => _orderTicket(orders[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ipBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surfaceCream,
      child: Row(
        children: [
          const Icon(Icons.dns, size: 18, color: AppColors.muted),
          const SizedBox(width: 8),
          const Text('Admin Host IP',
              style: TextStyle(fontSize: 13, color: AppColors.muted)),
          const Spacer(),
          SizedBox(
            width: 140,
            child: appTextField(
              context: context,
              label: 'IP',
              controller: _ipController,
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reconnect),
        ],
      ),
    );
  }

  Widget _filterBar() {
    final filters = [
      ('all', 'All'),
      (AppConstants.statusPending, 'Pending'),
      (AppConstants.statusPreparing, 'Preparing'),
      (AppConstants.statusReady, 'Ready'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in filters)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f.$2),
                  selected: _filter == f.$1,
                  onSelected: (_) => setState(() => _filter = f.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(_notifier.error ?? 'Connection error',
              style: const TextStyle(color: AppColors.error)),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _reconnect, child: const Text('Reconnect')),
        ],
      ),
    );
  }

  Widget _orderTicket(Order order) {
    final color = statusColor(order.status);
    final time = order.createdAt != null
        ? DateFormat.Hm().format(order.createdAt!)
        : '--:--';
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Text('#${order.id}',
                      style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Table ${order.tableNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(time,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
                statusChip(order.status),
              ],
            ),
            const Divider(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: order.items.map(_itemRow).toList(),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (order.status != AppConstants.statusReady &&
                    order.status != AppConstants.statusServed)
                  TextButton.icon(
                    onPressed: () => _cancel(order),
                    icon: const Icon(Icons.close, color: AppColors.error),
                    label: const Text('Cancel',
                        style: TextStyle(color: AppColors.error)),
                  )
                else
                  const SizedBox.shrink(),
                FilledButton.icon(
                  onPressed: () => _advance(order),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(_advanceLabel(order.status)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _advanceLabel(String status) => switch (status) {
        AppConstants.statusPending => 'Start',
        AppConstants.statusPreparing => 'Ready',
        AppConstants.statusReady => 'Serve',
        _ => 'Done',
      };

  Widget _itemRow(OrderItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('${item.quantity}×',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.name,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Text(formatMoney(item.price * item.quantity),
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ],
      ),
    );
  }
}
