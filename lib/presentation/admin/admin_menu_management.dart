library teashop_pos.presentation.admin.admin_menu_management;

import 'package:flutter/material.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/menu_item.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<MenuItem> _items = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _db.getMenuItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _toggle(MenuItem item) async {
    await _db.toggleMenuItemAvailability(item.id!, !item.available);
    await _load();
  }

  Future<void> _delete(MenuItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${item.name}" from the menu?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteMenuItem(item.id!);
      await _load();
    }
  }

  Future<void> _editOrAdd([MenuItem? existing]) async {
    final isEdit = existing != null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
        text: isEdit ? existing.price.toStringAsFixed(2) : '');
    final categoryCtrl = TextEditingController(text: existing?.category ?? '');
    final descCtrl = TextEditingController(text: existing?.description ?? '');
    bool available = existing?.available ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isEdit ? 'Edit Item' : 'New Menu Item',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  appTextField(
                      context: context, label: 'Name', controller: nameCtrl),
                  const SizedBox(height: 12),
                  appTextField(
                      context: context,
                      label: 'Category',
                      controller: categoryCtrl),
                  const SizedBox(height: 12),
                  appTextField(
                      context: context,
                      label: 'Description',
                      controller: descCtrl,
                      maxLines: 2),
                  const SizedBox(height: 12),
                  appTextField(
                      context: context,
                      label: 'Price',
                      controller: priceCtrl,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Available'),
                      const Spacer(),
                      Switch(
                          value: available,
                          onChanged: (v) => setState(() => available = v)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      appButton(
                          label: isEdit ? 'Save' : 'Add',
                          onPressed: () => Navigator.pop(context, true)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      final price = double.tryParse(priceCtrl.text) ?? 0;
      final item = MenuItem(
        id: isEdit ? existing.id : null,
        name: nameCtrl.text,
        category: categoryCtrl.text,
        description: descCtrl.text,
        price: price,
        available: available,
        createdAt: isEdit ? existing.createdAt : null,
      );
      if (isEdit) {
        await _db.updateMenuItem(item);
      } else {
        await _db.insertMenuItem(item);
      }
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Menu Items',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.tight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: appButton(
                      label: '+ Add Item', onPressed: () => _editOrAdd()),
                ),
              ),
            ],
          ),
        ),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_items.isEmpty)
          const Expanded(
              child: Center(
                  child: Text('No menu items. Add one to get started.')))
        else
          Expanded(
            child: ResponsiveGrid(
              compact: 1,
              medium: 2,
              expanded: 3,
              large: 4,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              childAspectRatio: 1.4,
              itemCount: _items.length,
              itemBuilder: (context, index) => _menuCard(_items[index]),
            ),
          ),
      ],
    );
  }

  Widget _menuCard(MenuItem item) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(item.category.isNotEmpty
                      ? item.category[0].toUpperCase()
                      : '?'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        '${item.category}  •  ${formatMoney(item.price)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                Switch(value: item.available, onChanged: (_) => _toggle(item)),
              ],
            ),
            if (item.description != null && item.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.description!,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: AppColors.error),
                  onPressed: () => _delete(item),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.primary),
                  onPressed: () => _editOrAdd(item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
