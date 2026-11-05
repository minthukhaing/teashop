library teashop_pos.presentation.waiter.waiter_screen;

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
import '../responsive_helpers.dart';
import 'waiter_login_screen.dart';

class WaiterScreen extends StatefulWidget {
  const WaiterScreen({super.key});

  @override
  State<WaiterScreen> createState() => _WaiterScreenState();
}

class _WaiterScreenState extends State<WaiterScreen> {
  final TextEditingController _ipController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<MenuItem> _menu = [];
  final Map<int, OrderItem> _cart = {};
  bool _loading = false;
  String? _error;

  List<Order> _orders = [];
  bool _ordersLoading = false;

  @override
  void initState() {
    super.initState();
    _ipController.text = AppConfig.instance.adminIp;
    _loadMenu();
    if (WaiterAuth.instance.can(WaiterPermissions.viewOrders)) {
      _loadOrders();
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    AppConfig.instance.adminIp = ip;
    AppConfig.instance.resetApi();

    setState(() {
      _loading = true;
      _error = null;
    });

    final healthy = await AppConfig.instance.api.checkHealth();
    if (!healthy) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach admin host at $ip:${AppConstants.serverPort}. '
            'Make sure the admin server is running.';
        _loading = false;
      });
      return;
    }

    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AppConfig.instance.api.fetchMenu();
      if (!mounted) return;
      setState(() {
        _menu = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach admin host. Check the IP address.';
        _loading = false;
      });
    }
  }

  void _addToCart(MenuItem item) {
    if (!WaiterAuth.instance.can(WaiterPermissions.takeOrders)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to take orders.')),
      );
      return;
    }
    setState(() {
      final existing = _cart[item.id];
      if (existing != null) {
        _cart[item.id!] =
            existing.copyWith(quantity: existing.quantity + 1);
      } else {
        _cart[item.id!] = OrderItem(
          menuItemId: item.id,
          name: item.name,
          price: item.price,
          quantity: 1,
        );
      }
    });
  }

  void _changeQty(int itemId, int delta) {
    setState(() {
      final current = _cart[itemId];
      if (current == null) return;
      final newQty = current.quantity + delta;
      if (newQty <= 0) {
        _cart.remove(itemId);
      } else {
        _cart[itemId] = current.copyWith(quantity: newQty);
      }
    });
  }

  int get _cartCount =>
      _cart.values.fold(0, (sum, item) => sum + item.quantity);
  double get _cartTotal =>
      _cart.values.fold(0.0, (sum, item) => sum + item.price * item.quantity);

  Map<String, List<MenuItem>> get _groupedMenu {
    final grouped = <String, List<MenuItem>>{};
    for (final item in _menu) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }
    return grouped;
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final items = _cart.values.toList();
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('Cart',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text('$_cartCount items',
                            style: const TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Cart is empty'),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          return ListTile(
                            title: Text(item.name),
                            subtitle: Text(formatMoney(item.price)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () {
                                    _changeQty(item.menuItemId!, -1);
                                    setSheetState(() {});
                                  },
                                ),
                                Text('${item.quantity}',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () {
                                    _changeQty(item.menuItemId!, 1);
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  if (items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Total',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              Text(formatMoney(_cartTotal),
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          appButton(
                            label: 'Send to Kitchen',
                            onPressed: () {
                              Navigator.pop(context);
                              _submitOrder();
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitOrder() async {
    if (_cart.isEmpty) return;
    final order = Order(
      tableNumber: 'T1',
      status: AppConstants.statusPending,
      total: _cartTotal,
      items: _cart.values.toList(),
      createdAt: DateTime.now(),
    );
    try {
      await AppConfig.instance.api.submitOrder(order);
      setState(() => _cart.clear());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order sent to kitchen!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send order: $e')),
      );
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _ordersLoading = true);
    try {
      final orders = await AppConfig.instance.api.fetchOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _ordersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _ordersLoading = false);
    }
  }

  Future<void> _cancelOrder(Order order) async {
    try {
      await AppConfig.instance.api.updateOrderStatus(
          order.id!, AppConstants.statusCancelled);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Order cancelled.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel order: $e')),
      );
    }
  }

  void _logout() {
    WaiterAuth.instance.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const WaiterLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bp = breakpointOfContext(context);
    final auth = WaiterAuth.instance;
    final canTakeOrders = auth.can(WaiterPermissions.takeOrders);
    final canViewOrders = auth.can(WaiterPermissions.viewOrders);
    final canCancelOrders = auth.can(WaiterPermissions.cancelOrders);
    final tabs = <Tab>[
      const Tab(text: 'Menu'),
      if (canViewOrders) const Tab(text: 'Orders'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(auth.isLoggedIn ? auth.displayNameOrUsername : 'Waiter'),
          actions: [
            if (canTakeOrders && _cartCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: _openCart,
                  icon: const Icon(Icons.shopping_cart),
                  label: Text('$_cartCount'),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
          ],
          bottom: canViewOrders ? TabBar(tabs: tabs) : null,
        ),
        body: GradientBackground(
          child: Column(
            children: [
              _ipBar(),
              if (_error != null) _errorView(),
              Expanded(
                child: canViewOrders
                    ? TabBarView(
                        children: [
                          _menuView(context, bp),
                          _ordersView(context, canCancelOrders),
                        ],
                      )
                    : _menuView(context, bp),
              ),
            ],
          ),
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: _connect),
        ],
      ),
    );
  }

  Widget _errorView() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppColors.error.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
          TextButton(onPressed: _loadMenu, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _ordersView(BuildContext context, bool canCancelOrders) {
    if (_ordersLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: AppColors.muted),
            SizedBox(height: 12),
            Text('No orders yet.'),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, i) => _orderTile(_orders[i], canCancelOrders),
      ),
    );
  }

  Widget _orderTile(Order order, bool canCancelOrders) {
    final canCancel = canCancelOrders &&
        order.status != AppConstants.statusServed &&
        order.status != AppConstants.statusCancelled;
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
                        '${order.createdAt != null ? AppConfig.instance.dateFormat.format(order.createdAt!) : "--:--"}  •  ${order.itemCount} items  •  ${formatMoney(order.total)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                statusChip(order.status),
              ],
            ),
            if (canCancel)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _cancelOrder(order),
                    icon: const Icon(Icons.cancel_outlined,
                        color: AppColors.error),
                    label: const Text('Cancel',
                        style: TextStyle(color: AppColors.error)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuView(BuildContext context, Breakpoint bp) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_menu.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.restaurant_menu, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('No menu items available.'),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _loadMenu, child: const Text('Retry')),
          ],
        ),
      );
    }
    final grouped = _groupedMenu;
    final categories = grouped.keys.toList()..sort();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final category = categories[index];
        final items = grouped[category]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            sectionTitle(context, category),
            const SizedBox(height: 8),
            ResponsiveGrid(
              compact: 2,
              medium: 3,
              expanded: 4,
              large: 5,
              childAspectRatio: 1.0,
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, i) => _menuItemCard(items[i]),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _menuItemCard(MenuItem item) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addToCart(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Text(item.description!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatMoney(item.price),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  Icon(Icons.add_circle, color: AppColors.primary, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
