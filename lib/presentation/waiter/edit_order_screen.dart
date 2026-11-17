library teashop_pos.presentation.waiter.edit_order_screen;

import 'package:flutter/material.dart';

import '../../core/auth/waiter_auth.dart';
import '../../core/auth/waiter_permissions.dart';
import '../../data/models/menu_item.dart';
import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../app_mode.dart';
import '../app_theme.dart';
import '../common_widgets.dart';

/// Dedicated, full-screen editor for an active, UNPAID order.
///
/// Replaces the old crowded popup/bottom-sheet flow: the waiter navigates here
/// with `Navigator.push` from the unpaid orders list (or a table's order card).
/// The screen shows every ordered menu item for that table with its unit
/// price, quantity and line subtotal — all in Kyat ("ကျပ်") — and provides
/// intuitive controls:
///
///  * `+` / `-` steppers to change an item's quantity,
///  * a trash button to remove a single line item,
///  * a menu list to add new items to the order,
///  * `Save Changes` which PUTs the updated order (the Admin Host recomputes
///    the total), and
///  * an optional `Delete Order` action (permission-gated) that removes the
///    whole unpaid order.
///
/// The screen pops with `true` when anything changed so the caller can reload
/// the unpaid orders list.
class EditOrderScreen extends StatefulWidget {
  const EditOrderScreen({
    super.key,
    required this.order,
    required this.menu,
    this.canDelete = false,
  });

  /// The unpaid order being edited (pending / preparing / ready).
  final Order order;

  /// Current menu, used by the "Add items" section.
  final List<MenuItem> menu;

  /// Whether the signed-in waiter may delete the whole order.
  final bool canDelete;

  @override
  State<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends State<EditOrderScreen> {
  /// Local editable copy of the order's line items, keyed by menu item id
  /// (falls back to a negative synthetic key for items no longer on the menu).
  late final Map<int, OrderItem> _editCart;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editCart = <int, OrderItem>{};
    for (final item in widget.order.items) {
      final key = item.menuItemId ?? -(item.id ?? _editCart.length);
      _editCart[key] = item;
    }
  }

  int _keyOf(OrderItem item) =>
      item.menuItemId ?? -(item.id ?? _editCart.length);

  List<OrderItem> get _items => _editCart.values.toList();

  int get _itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Live subtotal of the edited order, in Kyat.
  double get _total =>
      _items.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  void _changeQty(OrderItem item, int delta) {
    setState(() {
      final key = _keyOf(item);
      final current = _editCart[key];
      if (current == null) return;
      final newQty = current.quantity + delta;
      if (newQty <= 0) {
        _editCart.remove(key);
      } else {
        _editCart[key] = current.copyWith(quantity: newQty);
      }
    });
  }

  void _removeItem(OrderItem item) {
    setState(() => _editCart.remove(_keyOf(item)));
  }

  void _addItem(MenuItem menuItem) {
    setState(() {
      final existing = _editCart[menuItem.id];
      if (existing != null) {
        _editCart[menuItem.id!] =
            existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _editCart[menuItem.id!] = OrderItem(
          menuItemId: menuItem.id,
          name: menuItem.name,
          price: menuItem.price,
          quantity: 1,
        );
      }
    });
  }

  /// Saves the edited order.  The server recomputes the total from the
  /// submitted line items, so the local Kyat subtotal is only a preview.
  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'An order must keep at least one item. Use Delete Order to '
              'remove the whole order.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await AppConfig.instance.api
          .updateOrder(widget.order.copyWith(items: _items));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order updated.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update order: $e')),
      );
    }
  }

  /// Permanently deletes the whole unpaid order (with confirmation).
  Future<void> _deleteOrder() async {
    if (!widget.canDelete ||
        !WaiterAuth.instance.can(WaiterPermissions.cancelOrders)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Order #${widget.order.id}?'),
        content: Text(
            'This will permanently remove the unpaid order for table '
            '${widget.order.tableNumber} (${widget.order.itemCount} items, '
            '${formatKyat(widget.order.total)}). This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Order'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AppConfig.instance.api.deleteOrder(widget.order.id!);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #${widget.order.id} deleted.')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete order: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final items = _items;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Order #${order.id} — Table ${order.tableNumber}'),
        actions: [
          if (widget.canDelete)
            IconButton(
              tooltip: 'Delete whole order',
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _deleteOrder,
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Order summary header ──
          Container(
            width: double.infinity,
            color: AppColors.primary.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.table_restaurant,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Table ${order.tableNumber}  •  '
                    '${order.createdAt != null ? AppConfig.instance.dateFormat.format(order.createdAt!) : "--:--"}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                statusChip(order.status),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── Current items + add-items list ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                const Text('Ordered items',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'No items left — add one below or delete the whole '
                        'order instead.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                else
                  for (final item in items) _itemTile(item),
                const SizedBox(height: 16),
                const Text('Add items',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.muted)),
                const SizedBox(height: 4),
                if (widget.menu.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Menu unavailable — cannot add new items.',
                        style:
                            TextStyle(color: AppColors.muted, fontSize: 13)),
                  )
                else
                  for (final menuItem in widget.menu) _addMenuItemRow(menuItem),
              ],
            ),
          ),
          // ── Total + save bar (all amounts in Kyat) ──
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$_itemCount items',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted)),
                        Text(
                          formatKyat(_total),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.success),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: appButton(
                      label: 'Save Changes',
                      onPressed: (_saving || items.isEmpty) ? null : _save,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One ordered line item: name, unit price and line subtotal in Kyat, a
  /// `-`/`+` quantity stepper and a delete button.
  Widget _itemTile(OrderItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${formatKyat(item.price)} × ${item.quantity} = '
                    '${formatKyat(item.subtotal)}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _QtyButton(
              icon: Icons.remove_circle_outline,
              onPressed: () => _changeQty(item, -1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${item.quantity}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            _QtyButton(
              icon: Icons.add_circle_outline,
              onPressed: () => _changeQty(item, 1),
            ),
            IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.error),
              onPressed: () => _removeItem(item),
            ),
          ],
        ),
      ),
    );
  }

  /// One menu row in the "Add items" section with a `+` button.
  Widget _addMenuItemRow(MenuItem menuItem) {
    return InkWell(
      onTap: () => _addItem(menuItem),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                menuItem.name,
                style: const TextStyle(fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatKyat(menuItem.price),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              height: 28,
              child: IconButton(
                onPressed: () => _addItem(menuItem),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                tooltip: 'Add to order',
                icon: const Icon(Icons.add, size: 20, color: AppColors.success),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular quantity-stepper button used by the ordered item tiles.
class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, this.onPressed});

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
