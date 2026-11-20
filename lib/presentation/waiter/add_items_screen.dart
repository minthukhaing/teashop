library teashop_pos.presentation.waiter.add_items_screen;

import 'package:flutter/material.dart';

import '../../data/models/menu_item.dart';
import '../app_theme.dart';
import '../common_widgets.dart';

/// Dedicated full-screen menu picker used when editing an existing order.
///
/// Opened via `Navigator.push` from [EditOrderScreen]'s
/// "+ ပစ္စည်းအသစ် ထည့်မည်" button.  Shows the full menu grouped by
/// category with `+` / `-` quantity steppers (pre-seeded with the order's
/// current quantities) and all prices in Kyat ("ကျပ်").  Tapping `Done` pops
/// with a `Map<int, int>` of `menuItemId -> quantity` (entries with quantity
/// `0` mean "remove this item from the order").
class AddItemsScreen extends StatefulWidget {
  const AddItemsScreen({
    super.key,
    required this.menu,
    required this.initialQuantities,
  });

  /// The full menu to pick from.
  final List<MenuItem> menu;

  /// Current `menuItemId -> quantity` of the order being edited, used to
  /// pre-seed the steppers so the waiter sees what is already on the order.
  final Map<int, int> initialQuantities;

  @override
  State<AddItemsScreen> createState() => _AddItemsScreenState();
}

class _AddItemsScreenState extends State<AddItemsScreen> {
  /// `menuItemId -> quantity` being picked for the order.
  late final Map<int, int> _quantities;

  /// Currently selected category filter (`null` = All).
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    _quantities = Map<int, int>.from(widget.initialQuantities);
  }

  Map<String, List<MenuItem>> get _groupedMenu {
    final grouped = <String, List<MenuItem>>{};
    for (final item in widget.menu) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  int get _totalCount =>
      _quantities.values.fold(0, (sum, qty) => sum + (qty > 0 ? qty : 0));

  void _changeQty(MenuItem item, int delta) {
    setState(() {
      final current = _quantities[item.id] ?? 0;
      final next = (current + delta).clamp(0, 999);
      _quantities[item.id!] = next;
    });
  }

  void _done() => Navigator.of(context).pop(_quantities);

  @override
  Widget build(BuildContext context) {
    final grouped = _groupedMenu;
    final categories = _selectedCategory == null
        ? grouped.keys.toList()
        : [_selectedCategory!];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ပစ္စည်းအသစ် ထည့်မည်'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              onPressed: _done,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Category filter chips ──
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _selectedCategory == null,
                  onSelected: (_) => setState(() => _selectedCategory = null),
                ),
                const SizedBox(width: 6),
                for (final cat in grouped.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: _selectedCategory == cat,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = cat),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Menu item list ──
          Expanded(
            child: widget.menu.isEmpty
                ? const Center(
                    child: Text('Menu unavailable.',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: categories.length,
                    itemBuilder: (context, i) {
                      final cat = categories[i];
                      final items = grouped[cat]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                            child: Text(cat,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                          for (final item in items) _menuRow(item),
                        ],
                      );
                    },
                  ),
          ),
          // ── Bottom bar: picked count + Done ──
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$_totalCount items selected',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted),
                    ),
                  ),
                  Expanded(
                    child: appButton(label: 'Done', onPressed: _done),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One menu row: name, Kyat price and a `-`/`+` quantity stepper.
  Widget _menuRow(MenuItem item) {
    final qty = _quantities[item.id] ?? 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: item.imageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                item.imageUrl!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(Icons.fastfood),
              ),
            )
          : const Icon(Icons.fastfood),
      title: MenuItemNamePriceRow(
        name: item.name,
        price: item.price,
        nameStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        priceStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.success,
        ),
        gap: 10,
      ),
      subtitle: null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepButton(
            icon: Icons.remove_circle_outline,
            onPressed: qty > 0 ? () => _changeQty(item, -1) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$qty',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          _StepButton(
            icon: Icons.add_circle_outline,
            onPressed: () => _changeQty(item, 1),
          ),
        ],
      ),
    );
  }
}

/// Small circular quantity-stepper button.
class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        icon: Icon(icon, size: 22),
      ),
    );
  }
}
