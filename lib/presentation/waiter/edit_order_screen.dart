library teashop_pos.presentation.waiter.edit_order_screen;

import 'package:flutter/material.dart';

import '../../core/auth/waiter_auth.dart';
import '../../core/auth/waiter_permissions.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/menu_item.dart';
import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../app_mode.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import 'add_items_screen.dart';

/// Dedicated, full-screen editor for an active, UNPAID order.
///
/// Replaces the old crowded popup/bottom-sheet flow: the waiter navigates here
/// with `Navigator.push` from the unpaid orders list (or a table's order card).
/// The screen shows every ordered menu item for that table with its unit
/// price, quantity and line subtotal - all in Kyat ("ကျပ်") - and provides
/// intuitive controls:
///
///  * `+` / `-` steppers to change an item's quantity,
///  * a trash button to remove a single line item,
///  * a prominent "+ ပစ္စည်းအသစ် ထည့်မည်" button that navigates (via
///    `Navigator.push`) to the dedicated menu picker ([AddItemsScreen]) to
///    add new items to this order cleanly,
///  * `Save Changes` which PUTs the updated order (the Admin Host recomputes
///    the total),
///  * an optional `Delete Order` action (permission-gated) that removes the
///    whole unpaid order, and
///  * `ငွေရှင်းမည် (Checkout)` (permission-gated) which opens a payment
///    dialog - pick a method (Cash / KPay / Wave Pay), enter the amount
///    received for cash and see the change in Kyat - then marks the order
///    PAID on the Admin Host.
///
/// Role-based permissions (granted per-waiter by the Admin):
///  * `edit_orders` - without it the screen is a READ-ONLY view: steppers,
///    delete buttons, "Add Items" and "Save" are disabled.
///  * `process_payments` - without it the Checkout button is hidden.
///  * `cancel_orders` (+ `canDelete`) - gates deleting the whole order.
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

  /// Whether the signed-in waiter may edit this order's items at all
  /// (Admin-granted `edit_orders` permission).  When false the screen becomes
  /// a read-only view: steppers, delete buttons, "Add Items" and "Save" are
  /// all disabled.
  bool get _canEdit => WaiterAuth.instance.can(WaiterPermissions.editOrders);

  /// Whether the signed-in waiter may settle the bill (Admin-granted
  /// `process_payments` permission).  Controls the Checkout button.
  bool get _canCheckout =>
      WaiterAuth.instance.can(WaiterPermissions.processPayments);

  int _keyOf(OrderItem item) =>
      item.menuItemId ?? -(item.id ?? _editCart.length);

  List<OrderItem> get _items => _editCart.values.toList();

  int get _itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Live subtotal of the edited order, in Kyat.
  double get _total =>
      _items.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  void _changeQty(OrderItem item, int delta) {
    if (!_canEdit) return;
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
    if (!_canEdit) return;
    setState(() => _editCart.remove(_keyOf(item)));
  }

  /// Opens the dedicated full-screen menu picker ([AddItemsScreen]) via
  /// `Navigator.push` so the waiter can add new items to THIS order cleanly.
  /// The picker is pre-seeded with the order's current quantities and pops
  /// with a `menuItemId -> quantity` map which is merged back into the local
  /// editable cart.  Off-menu items (no `menuItemId`) are always preserved.
  Future<void> _openAddItems() async {
    if (!_canEdit) return;
    final initialQuantities = <int, int>{};
    for (final entry in _editCart.entries) {
      final item = entry.value;
      if (item.menuItemId != null) {
        initialQuantities[item.menuItemId!] = item.quantity;
      }
    }

    final result = await Navigator.of(context).push<Map<int, int>>(
      MaterialPageRoute(
        builder: (_) => AddItemsScreen(
          menu: widget.menu,
          initialQuantities: initialQuantities,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final menuById = {for (final m in widget.menu) m.id: m};
    setState(() {
      for (final entry in result.entries) {
        final menuItem = menuById[entry.key];
        if (menuItem == null) continue;
        final qty = entry.value;
        if (qty <= 0) {
          _editCart.remove(entry.key);
        } else {
          _editCart[entry.key] = OrderItem(
            menuItemId: menuItem.id,
            name: menuItem.name,
            price: menuItem.price,
            quantity: qty,
          );
        }
      }
    });
  }

  /// Saves the edited order.  The server recomputes the total from the
  /// submitted line items, so the local Kyat subtotal is only a preview.
  Future<void> _save() async {
    if (!_canEdit) return;
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

  /// Opens the payment dialog, settles the bill and marks the order PAID.
  ///
  /// Any unsaved edits are pushed to the Admin Host first (so the paid total
  /// matches the on-screen items), then the order is checked out with the
  /// chosen payment method.  On success the screen pops with `true` so the
  /// caller reloads the unpaid orders list.
  Future<void> _checkout() async {
    if (!_canCheckout) return;
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cannot check out an order with no items.')),
      );
      return;
    }

    final payment = await showDialog<_PaymentResult>(
      context: context,
      builder: (_) => _PaymentDialog(total: _total),
    );
    if (payment == null || !mounted) return;

    setState(() => _saving = true);
    try {
      // Push unsaved edits first so the settled total matches the screen.
      if (_canEdit) {
        await AppConfig.instance.api
            .updateOrder(widget.order.copyWith(items: _items));
      }
      await AppConfig.instance.api
          .checkoutOrder(widget.order.id!, payment.method);
      if (!mounted) return;
      final change = payment.received - _total;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Order #${widget.order.id} paid via ${payment.methodLabel}.'
              '${payment.received > 0 && change > 0 ? '  Change: ${formatKyat(change)}.' : ''}'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout failed: $e')),
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
        title: Text('Edit Order #${order.id} - Table ${order.tableNumber}'),
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
                    'Table ${order.tableNumber} - '
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
          // ── Read-only banner when the waiter lacks edit permission ──
          if (!_canEdit)
            Container(
              width: double.infinity,
              color: AppColors.warning.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: AppColors.warning),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Read-only view - your account is not allowed to edit '
                      'orders. Ask an Admin for the "Edit orders" permission.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          // ── Clean ordered-items list only ──
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.remove_shopping_cart_outlined,
                            size: 56, color: AppColors.muted),
                        SizedBox(height: 12),
                        Text('No items left on this order.',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('Add items or delete the whole order.',
                            style: TextStyle(
                                color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _itemTile(items[i]),
                  ),
          ),
          // ── Prominent "Add Items" navigation button ──
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.tonalIcon(
                onPressed:
                    (widget.menu.isEmpty || !_canEdit) ? null : _openAddItems,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('ပစ္စည်းအသစ် ထည့်မည် (Add Items)'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success.withOpacity(0.12),
                  foregroundColor: AppColors.success,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
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
                  if (_canCheckout) ...[
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: (_saving || items.isEmpty) ? null : _checkout,
                        icon: const Icon(Icons.payments_outlined),
                        label: const Text('ငွေရှင်းမည် (Checkout)'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: appButton(
                      label: 'Save Changes',
                      onPressed: (_saving || items.isEmpty || !_canEdit)
                          ? null
                          : _save,
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
                    '${formatKyat(item.price)} x${item.quantity} = '
                    '${formatKyat(item.subtotal)}',
                    style:
                        const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
            _QtyButton(
              icon: Icons.remove_circle_outline,
              onPressed: _canEdit ? () => _changeQty(item, -1) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('${item.quantity}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            _QtyButton(
              icon: Icons.add_circle_outline,
              onPressed: _canEdit ? () => _changeQty(item, 1) : null,
            ),
            IconButton(
              tooltip: 'Remove item',
              icon: const Icon(Icons.delete_outline,
                  size: 20, color: AppColors.error),
              onPressed: _canEdit ? () => _removeItem(item) : null,
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

/// Outcome of a successful payment-dialog confirmation.
class _PaymentResult {
  const _PaymentResult({
    required this.method,
    required this.methodLabel,
    this.received = 0,
  });

  /// Machine key sent to the server (e.g. `cash`, `kpay`).
  final String method;

  /// Human-readable method name for snackbars.
  final String methodLabel;

  /// Amount actually received in Kyat (cash only; 0 for digital methods).
  final double received;
}

/// Payment / checkout dialog: choose a payment method (Cash, KPay, Wave Pay),
/// enter the amount received for cash and see the change - all in Kyat.
///
/// Pops with a [_PaymentResult] when confirmed, or `null` when cancelled.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total});

  /// Bill total to settle, in Kyat.
  final double total;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  static const List<({String id, String label, IconData icon})> _methods = [
    (id: 'cash', label: 'ငွေသား (Cash)', icon: Icons.payments),
    (id: 'kpay', label: 'KPay', icon: Icons.phone_android),
    (id: 'wavepay', label: 'Wave Pay', icon: Icons.waves),
  ];

  String _method = 'cash';
  final TextEditingController _receivedCtrl = TextEditingController();

  @override
  void dispose() {
    _receivedCtrl.dispose();
    super.dispose();
  }

  double get _received => double.tryParse(_receivedCtrl.text.trim()) ?? 0;

  double get _change => _received - widget.total;

  bool get _canConfirm =>
      _method != 'cash' || _received >= widget.total;

  void _confirm() {
    final label =
        _methods.firstWhere((m) => m.id == _method, orElse: () => _methods.first).label;
    Navigator.of(context).pop(_PaymentResult(
      method: _method,
      methodLabel: label,
      received: _method == 'cash' ? _received : 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ငွေရှင်းမည် (Checkout)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total to pay: ${formatKyat(widget.total)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('Payment method',
                style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _methods)
                  ChoiceChip(
                    label: Text(m.label),
                    avatar: Icon(m.icon,
                        size: 18,
                        color: _method == m.id
                            ? Colors.white
                            : AppColors.primary),
                    selected: _method == m.id,
                    onSelected: (_) => setState(() => _method = m.id),
                  ),
              ],
            ),
            if (_method == 'cash') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _receivedCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'ရယူသည့် ပမာဏ (Amount received, ${AppConstants.currency})',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Text(
                _received <= 0
                    ? 'Enter the amount received from the customer.'
                    : _change >= 0
                        ? 'ပြန်အမ်းငွေ (Change): ${formatKyat(_change)}'
                        : 'Not enough - still owe ${formatKyat(-_change)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _received <= 0 || _change >= 0
                      ? AppColors.success
                      : AppColors.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('မလုပ်တော့ပါ (Cancel)'),
        ),
        FilledButton.icon(
          onPressed: _canConfirm ? _confirm : null,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('ငွေရှင်းပြီး (Confirm)'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
