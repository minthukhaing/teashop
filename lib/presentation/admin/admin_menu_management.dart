library teashop_pos.presentation.admin.admin_menu_management;

import 'package:flutter/material.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/menu_item.dart';
import '../app_theme.dart';
import '../common_widgets.dart';

/// Admin menu management, styled to match the waiter's menu view:
/// horizontal category pills + minimalist divider-separated item rows.
/// Tap a row to edit it; use the trailing icon to delete it.
class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key, this.initialCategory});

  /// Optional category to pre-filter the list with (used when navigating
  /// here from the Categories screen).
  final String? initialCategory;

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  final AppDatabase _db = AppDatabase.instance;
  List<MenuItem> _items = [];
  bool _loading = false;
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _db.getMenuItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      // Drop the filter if the selected category no longer exists.
      if (_selectedCategory != null &&
          !items.any((i) => i.category == _selectedCategory)) {
        _selectedCategory = null;
      }
    });
  }

  List<String> get _categories =>
      _items.map((i) => i.category).toSet().toList()..sort();

  List<MenuItem> get _filtered => _selectedCategory == null
      ? _items
      : _items.where((i) => i.category == _selectedCategory).toList();

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
    final categories = await _db.getCategories();
    String? selectedCategory = existing?.category;
    if (selectedCategory != null && !categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }
    if (categories.isEmpty) categories.add('General');
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
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map((c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(c),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => selectedCategory = v),
                  ),
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
        category: selectedCategory ?? '',
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
        else ...[
          _categoryPills(),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No items in this category.',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) => _menuItemRow(_filtered[i]),
                    separatorBuilder: (_, _) => const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: Color(0x1F000000), // 12% black hairline
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  /// Horizontal category filter pills, same pattern as the waiter's menu view.
  Widget _categoryPills() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _categoryPill(label: 'All', icon: Icons.apps, category: null),
          for (final category in _categories)
            _categoryPill(
              label: category,
              icon: _categoryIcon(category),
              category: category,
            ),
        ],
      ),
    );
  }

  Widget _categoryPill({
    required String label,
    required IconData icon,
    required String? category,
  }) {
    final active = _selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.primary : AppColors.accent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _selectedCategory = category),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Picks a sensible icon for a menu category name (same as the waiter view).
  IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('tea') || c.contains('coffee') || c.contains('လက်ဖက်')) {
      return Icons.local_cafe;
    }
    if (c.contains('juice') || c.contains('drink') || c.contains('soft')) {
      return Icons.local_drink;
    }
    if (c.contains('dessert') || c.contains('sweet') || c.contains('အချို')) {
      return Icons.icecream;
    }
    if (c.contains('soup') || c.contains('ဟင်း')) return Icons.ramen_dining;
    if (c.contains('rice') || c.contains('ထမင်း')) return Icons.rice_bowl;
    return Icons.restaurant;
  }

  /// Minimalist item row matching the waiter's menu: name on the left, price
  /// and edit/delete actions on the right, separated by thin dividers.
  /// Tapping the row also opens the edit dialog.
  Widget _menuItemRow(MenuItem item) {
    return InkWell(
      onTap: () => _editOrAdd(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: MenuItemNamePriceRow(
                name: item.name,
                price: item.price,
                nameStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF212121),
                ),
                priceStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 20, color: AppColors.primary),
              tooltip: 'Edit',
              onPressed: () => _editOrAdd(item),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.error),
              tooltip: 'Delete',
              onPressed: () => _delete(item),
            ),
          ],
        ),
      ),
    );
  }
}
