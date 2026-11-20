library teashop_pos.presentation.admin.screens.admin_tables_screen;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/myanmar_text.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/table.dart';

/// Admin table management screen.
///
/// The Admin Host owns the canonical `tables` list in its local SQLite
/// database.  This screen lets the Admin add new tables and delete existing
/// ones (blocked when the table still has unpaid orders).  Changes are
/// persisted immediately and are automatically visible to Waiter clients,
/// which sync the floor plan from `GET /api/tables`.
class AdminTablesScreen extends StatefulWidget {
  const AdminTablesScreen({super.key});

  @override
  State<AdminTablesScreen> createState() => _AdminTablesScreenState();
}

class _AdminTablesScreenState extends State<AdminTablesScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<TableModel> _tables = [];
  Map<String, int> _activeOrderCounts = {};
  bool _loading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    // Pick up table changes made through the Shelf API (another Admin session
    // or a remote client) without requiring the operator to leave this screen.
    _refreshTimer = Timer.periodic(AppConstants.ordersPollInterval, (_) {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Reloads tables and their exact unpaid-order counts from the Admin Host's
  /// SQLite database.  [silent] refreshes in the background without replacing
  /// the list with a spinner (used by the periodic sync).
  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final tables = await _db.getTables();
      final counts = <String, int>{};
      await Future.wait(tables.map((table) async {
        counts[table.number] =
            await _db.countActiveOrdersForTable(table.number);
      }));
      if (!mounted) return;
      setState(() {
        _tables = tables;
        _activeOrderCounts = counts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Opens the add-table dialog.  Validates a non-empty unique number before
  /// inserting.
  Future<void> _addTable() async {
    final numberCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '4');
    bool? result;
    result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberCtrl,
              decoration: const InputDecoration(
                labelText: 'Table number',
                hintText: 'e.g. T13',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capacityCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacity (seats)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final number = MyanmarText.normalize(numberCtrl.text.trim());
              if (number.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a table number.')),
                );
                return;
              }
              final existing = await _db.getTableByNumber(number);
              if (existing != null) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('Table "$number" already exists.')),
                );
                return;
              }
              if (!ctx.mounted) return;
              final capacity = int.tryParse(capacityCtrl.text);
              if (capacity == null || capacity <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                      content: Text('Capacity must be a positive number.')),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    // Capture values BEFORE disposing controllers.
    final number = MyanmarText.normalize(numberCtrl.text.trim());
    final capacityText = capacityCtrl.text;
    numberCtrl.dispose();
    capacityCtrl.dispose();
    if (result == true && number.isNotEmpty) {
      final capacity = int.tryParse(capacityText) ?? 4;
      try {
        await _db.insertTable(TableModel(
          number: number,
          capacity: capacity,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Table "$number" added.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add table: $e')),
        );
      }
    }
  }

  /// Deletes [table].  Refused (with a message) when the table has unpaid
  /// orders so active bills are never orphaned.
  Future<void> _deleteTable(TableModel table) async {
    // Re-check directly against the database: the cached count may be stale
    // and the 100-row snapshot used previously could miss unpaid orders.
    final activeOrders =
        await _db.countActiveOrdersForTable(table.number);
    if (activeOrders > 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Cannot delete "${table.number}": it has $activeOrders unpaid order(s). '
              'Close or move them first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Table?'),
        content: Text('Delete table "${table.number}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _db.deleteTable(table.id!);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Table "${table.number}" deleted.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete table: $e')),
        );
      }
    }
  }

  Color _statusColor(TableModel table, int activeOrders) {
    if (!table.isActive) return Colors.grey;
    if (activeOrders > 0) return AppColors.warning;
    return AppColors.success;
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
              const SizedBox(width: 10),
              Text(
                '${_tables.length} ${_tables.length == 1 ? 'table' : 'tables'}',
                style: const TextStyle(fontSize: 13, color: AppColors.muted),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _loading ? null : _addTable,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Table'),
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: _tables.isEmpty
                ? const Center(
                    child: Text(
                      'No tables yet. Tap "Add Table" to create one.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _tables.length,
                    itemBuilder: (context, i) {
                      final table = _tables[i];
                      final activeOrders =
                          _activeOrderCounts[table.number] ?? 0;
                      final occupied = activeOrders > 0;
                      final statusColor = _statusColor(table, activeOrders);
                      final details = <String>[
                        '${table.capacity} seats',
                        if (occupied) '$activeOrders unpaid order(s)',
                        if (!table.isActive) 'Inactive',
                      ];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: statusColor.withOpacity(0.15),
                            child: Icon(
                              occupied
                                  ? Icons.table_bar
                                  : table.isActive
                                      ? Icons.table_restaurant_outlined
                                      : Icons.table_bar_outlined,
                              color: statusColor,
                            ),
                          ),
                          title: Text(
                            table.number,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            details.join('  \u2022  '),
                            style: TextStyle(
                              color: table.isActive
                                  ? AppColors.muted
                                  : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (occupied)
                                const Icon(Icons.hourglass_empty,
                                    size: 18, color: AppColors.warning),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: occupied
                                        ? AppColors.muted
                                        : AppColors.error),
                                tooltip: occupied
                                    ? 'Cannot delete: table has active orders'
                                    : 'Delete table',
                                onPressed: occupied
                                    ? null
                                    : () => _deleteTable(table),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }
}
