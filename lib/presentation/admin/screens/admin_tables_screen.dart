library teashop_pos.presentation.admin.screens.admin_tables_screen;

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/order.dart';

/// Tables screen – overview of all tables and their status.
class AdminTablesScreen extends StatefulWidget {
  const AdminTablesScreen({super.key});

  @override
  State<AdminTablesScreen> createState() => _AdminTablesScreenState();
}

class _AdminTablesScreenState extends State<AdminTablesScreen> {
  final AppDatabase _db = AppDatabase.instance;
  Map<int, Order?> _tableOrders = {};
  int _totalTables = 10;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final orders = await _db.getOrders(limit: 100);
      if (!mounted) return;
      final activeOrders = orders.where((o) =>
        o.status == 'pending' || o.status == 'preparing' || o.status == 'ready'
      ).toList();
      final map = <int, Order?>{};
      for (int i = 1; i <= _totalTables; i++) {
        map[i] = null;
      }
      for (final o in activeOrders) {
        map[o.tableNumber] = o;
      }
      setState(() {
        _tableOrders = map;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setTableCount() async {
    final ctrl = TextEditingController(text: _totalTables.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('စားပွဲအရေအတွက်'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'စုစုပေါင်းစားပွဲ'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('မလုပ်တော့ပါ')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.sidebarBg,
                foregroundColor: Colors.white,
              ),
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text)),
              child: const Text('သတ်မှတ်မည်')),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result > 0) {
      setState(() => _totalTables = result);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(
            children: [
              const Text('စားပွဲများ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              // Legend
              Row(
                children: [
                  _legendDot(AppColors.success, 'လွတ်'),
                  const SizedBox(width: 8),
                  _legendDot(AppColors.warning, 'မှာ'),
                  const SizedBox(width: 8),
                  _legendDot(AppColors.error.withOpacity(0.7), 'အသုံးပြုဆဲ'),
                ],
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _setTableCount,
                icon: const Icon(Icons.settings),
                tooltip: 'စားပွဲ အရေအတွက် ပြင်ဆင်',
                color: AdminColors.sidebarBg,
              ),
            ],
          ),
        ),
        // Status summary row
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AdminColors.sidebarBg.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem('စုစုပေါင်း', _totalTables.toString(), Colors.grey),
              _summaryItem(
                'အသုံးပြုဆဲ',
                _tableOrders.values.where((o) => o != null).length.toString(),
                AppColors.warning,
              ),
              _summaryItem(
                'လွတ်',
                _tableOrders.values.where((o) => o == null).length.toString(),
                AppColors.success,
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AdminColors.sidebarBg,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.0,
                ),
                itemCount: _totalTables,
                itemBuilder: (context, index) {
                  final tableNum = index + 1;
                  final order = _tableOrders[tableNum];
                  return _tableCard(tableNum, order);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _tableCard(int tableNum, Order? order) {
    final occupied = order != null;
    final statusColor = occupied
        ? (order.status == 'ready' ? AppColors.success : AppColors.warning)
        : Colors.grey.shade200;
    final bgColor = occupied
        ? (order.status == 'ready'
            ? AppColors.success.withOpacity(0.1)
            : AppColors.warning.withOpacity(0.1))
        : Colors.grey.shade50;

    return GestureDetector(
      onTap: occupied ? () => _showTableDetail(tableNum, order) : null,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: occupied ? statusColor : Colors.grey.shade300,
            width: occupied ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chair,
              size: 28,
              color: occupied ? statusColor : Colors.grey.shade400,
            ),
            const SizedBox(height: 6),
            Text(
              'T$tableNum',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: occupied ? statusColor : Colors.grey.shade600,
              ),
            ),
            if (occupied)
              Text(
                order.status == 'ready' ? 'အဆင်သင့်' : 'မှာ',
                style: TextStyle(fontSize: 10, color: statusColor),
              )
            else
              Text('လွတ်',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  void _showTableDetail(int tableNum, Order order) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('စားပွဲ $tableNum',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('မှာယူမှုနံပါတ်: #${order.id}',
                style: const TextStyle(color: AppColors.muted)),
            Text('အရေအတွက်: ${order.itemCount} items',
                style: const TextStyle(color: AppColors.muted)),
            Text('စုစုပေါင်း: ${formatMoney(order.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ],
    );
  }
}

