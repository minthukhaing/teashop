library teashop_pos.presentation.waiter.cart_screen;

import 'package:flutter/material.dart';

import '../../data/models/order_item.dart';
import '../app_theme.dart';
import '../common_widgets.dart';

/// Dedicated, full-screen Cart page.
///
/// Replaces the old crowded bottom-sheet popup: tapping the cart badge in the
/// main menu navigates here via `Navigator.push`.  The screen shows:
///
///  * the current table number (e.g. "Table T-9" or "Parcel") at the top,
///  * every selected item with its unit price, quantity and line subtotal - ///    all in Kyat ("ကျပ်") - plus `-`/`+` quantity steppers and a delete
///    button per line,
///  * a live Kyat total, and
///  * a prominent `Send to Kitchen` primary button that finalizes the order
///    through the [onSubmit] callback (which submits it to the local
///    server/database).
///
/// Navigation contract:
///  * Backing out pops with the edited `List<OrderItem>` so the caller can
///    sync its cart, and
///  * a successful `Send to Kitchen` pops with `true`.
class CartScreen extends StatefulWidget {
  const CartScreen({
    super.key,
    required this.tableLabel,
    required this.items,
    required this.onSubmit,
  });

  /// Human-readable table identifier shown at the top, e.g. `T-9` or `Parcel`.
  final String tableLabel;

  /// The cart's line items when the screen is opened.
  final List<OrderItem> items;

  /// Submits the finalized order to the local server/database.
  /// Returns `true` on success (the screen then pops with `true`).
  final Future<bool> Function(List<OrderItem> items) onSubmit;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  /// Local editable copy of the cart, keyed by menu item id.
  late final Map<int, OrderItem> _cart;

  /// True while the order is being submitted ("Send to Kitchen").
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _cart = <int, OrderItem>{};
    for (final item in widget.items) {
      _cart[item.menuItemId ?? -(item.id ?? _cart.length)] = item;
    }
  }

  int _keyOf(OrderItem item) =>
      item.menuItemId ?? -(item.id ?? _cart.length);

  List<OrderItem> get _items => _cart.values.toList();

  int get _itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Live total of the cart, in Kyat.
  double get _total =>
      _items.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  void _changeQty(OrderItem item, int delta) {
    setState(() {
      final key = _keyOf(item);
      final current = _cart[key];
      if (current == null) return;
      final newQty = current.quantity + delta;
      if (newQty <= 0) {
        _cart.remove(key);
      } else {
        _cart[key] = current.copyWith(quantity: newQty);
      }
    });
  }

  void _removeItem(OrderItem item) {
    setState(() => _cart.remove(_keyOf(item)));
  }

  /// Finalizes the order: hands the current items to [CartScreen.onSubmit]
  /// (which submits to the local server/database) and pops on success.
  Future<void> _sendToKitchen() async {
    if (_items.isEmpty || _sending) return;
    setState(() => _sending = true);
    final success = await widget.onSubmit(_items);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    return PopScope(
      // Sync the edited cart back to the caller when backing out.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(items);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cart'),
          leading: IconButton(
            tooltip: 'Back to menu',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(items),
          ),
        ),
        body: Column(
          children: [
            // ── Table number header ──
            Container(
              width: double.infinity,
              color: AppColors.primary.withOpacity(0.06),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.table_restaurant,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Table ${widget.tableLabel}',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text('$_itemCount items',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Clean cart items list ──
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.remove_shopping_cart_outlined,
                              size: 56, color: AppColors.muted),
                          SizedBox(height: 12),
                          Text('Cart is empty.',
                              style: TextStyle(
                                  color: AppColors.muted, fontSize: 14)),
                          SizedBox(height: 4),
                          Text('Go back and add items from the menu.',
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
            // ── Total + Send to Kitchen bar (all amounts in Kyat) ──
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
                          const Text('Total',
                              style: TextStyle(
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
                        label: 'Send to Kitchen',
                        loading: _sending,
                        onPressed:
                            (_sending || items.isEmpty) ? null : _sendToKitchen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One cart line item: name, unit price and line subtotal in Kyat, a
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
}

/// Small circular quantity-stepper button used by the cart item tiles.
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
