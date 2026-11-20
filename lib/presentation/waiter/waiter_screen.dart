library teashop_pos.presentation.waiter.waiter_screen;

import 'package:flutter/material.dart';

import '../../core/auth/waiter_auth.dart';
import '../../core/auth/waiter_permissions.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/menu_item.dart';
import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../../printer/bluetooth_printer_service.dart';
import '../../printer/printer_dialog.dart';
import '../app_mode.dart';
import '../app_theme.dart';
import '../common_widgets.dart';
import '../responsive_helpers.dart';
import '../voucher_screen.dart';
import 'edit_order_screen.dart';
import 'waiter_login_screen.dart';

/// Minimalist circular "+" action button used by the menu list rows.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        splashRadius: 18,
        tooltip: 'Add to order',
        icon: const Icon(Icons.add, size: 20, color: AppColors.success),
      ),
    );
  }
}

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
  bool _menuLoading = false;
  String? _error;

  /// Controller for the instant menu search field.
  final TextEditingController _searchController = TextEditingController();

  /// State for category filtering
  String _selectedCategory = 'All';

  /// State for quantity tracking per menu item
  final Map<int, int> _itemQuantities = {};

  List<Order> _orders = [];
  bool _ordersLoading = false;

  /// Index of the currently selected bottom navigation tab.
  int _currentIndex = 0;

  /// Id of the order card currently expanded to show its item details.
  int? _expandedOrderId;

  /// The table the waiter is currently taking an order for.
  String? _selectedTable;

  /// True when the Parcel (takeaway) tab is active.
  bool get _isParcelMode => _currentIndex == 3;

  /// Filtered list combining search query AND category chip selection
  List<MenuItem> get filteredItems {
    final query = _searchController.text.trim().toLowerCase();
    final isAll = _selectedCategory.isEmpty ||
        _selectedCategory.toLowerCase() == 'all';

    return _menu.where((item) {
      // Filter by category (handles Myanmar text & case-insensitivity)
      final categoryName = item.category.trim();
      final categoryMatch = isAll ||
          categoryName.toLowerCase() ==
              _selectedCategory.trim().toLowerCase();

      // Filter by search query - search in name using contains
      final searchMatch =
          query.isEmpty || item.name.toLowerCase().contains(query);

      return categoryMatch && searchMatch;
    }).toList();
  }

  /// Menu items grouped by category based on currently filtered items
  Map<String, List<MenuItem>> get _filteredGroupedMenu {
    final grouped = <String, List<MenuItem>>{};
    for (final item in filteredItems) {
      final category =
          item.category.trim().isEmpty ? 'Other' : item.category.trim();
      grouped.putIfAbsent(category, () => []).add(item);
    }
    return grouped;
  }

  /// Number of tables shown on the Tables tab.
  static const int _tableCount = 12;

  /// Statuses that mean a table is still occupied by an active order.
  static const List<String> _activeStatuses = [
    AppConstants.statusPending,
    AppConstants.statusPreparing,
    AppConstants.statusReady,
  ];

  Timer? _ordersTimer;

  void _startOrdersTimer() {
    _ordersTimer?.cancel();
    _ordersTimer = Timer.periodic(AppConstants.ordersPollInterval, (_) {
      if (!mounted) return;
      if (WaiterAuth.instance.can(WaiterPermissions.viewOrders)) {
        _loadOrders(silent: true);
      }
    });
  }

  void _stopOrdersTimer() {
    _ordersTimer?.cancel();
    _ordersTimer = null;
  }

  @override
  void initState() {
    super.initState();
    _ipController.text = AppConfig.instance.adminIp;
    _loadMenu();
    if (WaiterAuth.instance.can(WaiterPermissions.viewOrders)) {
      _loadOrders();
      _startOrdersTimer();
    }
  }

  @override
  void dispose() {
    _stopOrdersTimer();
    _ipController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;
    AppConfig.instance.adminIp = ip;
    AppConfig.instance.resetApi();

    setState(() {
      _menuLoading = true;
      _error = null;
    });

    final healthy = await AppConfig.instance.api.checkHealth();
    if (!healthy) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach admin host at $ip:${AppConstants.serverPort}. '
            'Make sure the admin server is running.';
        _menuLoading = false;
      });
      return;
    }

    _loadMenu();
    if (WaiterAuth.instance.can(WaiterPermissions.viewOrders)) {
      _loadOrders();
      _startOrdersTimer();
    }
  }

  Future<void> _loadMenu() async {
    setState(() {
      _menuLoading = true;
      _error = null;
    });
    try {
      final items = await AppConfig.instance.api.fetchMenu();
      if (!mounted) return;
      setState(() {
        _menu = items;
        _menuLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Cannot reach admin host. Check the IP address.';
        _menuLoading = false;
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

  /// True when an order can be submitted: parcel orders always can, table
  /// orders require a selected table. When an active unpaid order exists,
  /// new items are automatically merged and appended to that table's bill.
  bool get canTakeNewOrder {
    if (_isParcelMode) return true;
    if (_selectedTable == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a table first (Tables tab).')),
      );
      return false;
    }
    return true;
  }

  /// Whether [table] currently has a pending/preparing/ready order.
  bool _hasActiveOrder(String table) => _orders.any(
      (o) => o.tableNumber == table && _activeStatuses.contains(o.status));

  /// The latest active order for [table], if any.
  Order? _activeOrderFor(String table) {
    final matches =
        _orders.where((o) => o.tableNumber == table && _activeStatuses.contains(o.status)).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) => (b.createdAt ?? DateTime(2000))
        .compareTo(a.createdAt ?? DateTime(2000)));
    return matches.first;
  }

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
                              if (canTakeNewOrder) _submitOrder();
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
    if (!canTakeNewOrder) return;
    final order = Order(
      tableNumber: _isParcelMode ? 'Parcel' : _selectedTable!,
      status: AppConstants.statusPending,
      total: _cartTotal,
      waiterName: WaiterAuth.instance.displayNameOrUsername,
      items: _cart.values.toList(),
      createdAt: DateTime.now(),
    );
    try {
      await AppConfig.instance.api.submitOrder(order);
      setState(() => _cart.clear());
      // Immediately reload orders so Orders screen and Tables reflect it in real time
      await _loadOrders(silent: true);
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

  Future<void> _loadOrders({bool silent = false}) async {
    if (!silent) {
      setState(() => _ordersLoading = true);
    }
    try {
      // Only fetch ACTIVE orders whose bill has not been paid/cleared yet
      // (pending / preparing / ready).  Served and cancelled orders are
      // excluded server-side via the `unpaid=true` filter.
      final orders = await AppConfig.instance.api.fetchOrders(unpaidOnly: true);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        if (_expandedOrderId != null &&
            !_orders.any((o) => o.id == _expandedOrderId)) {
          _expandedOrderId = null;
        }
        _ordersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) {
        setState(() => _ordersLoading = false);
      }
    }
  }

  /// Toggles the expanded (item-details) state of an order card.
  void _toggleOrderExpanded(Order order) {
    setState(() {
      _expandedOrderId = _expandedOrderId == order.id ? null : order.id;
    });
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

  /// Opens the dedicated full-screen Edit Order screen (no popup): quantity
  /// steppers on the existing line items, per-item delete, plus a menu picker
  /// to add new items.  Saving PUTs the updated order to the Admin Host, which
  /// recomputes the total.  When the screen reports changes, the unpaid orders
  /// list is reloaded.
  Future<void> _editOrder(Order order) async {
    if (!WaiterAuth.instance.can(WaiterPermissions.takeOrders)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to edit orders.')),
      );
      return;
    }

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditOrderScreen(
          order: order,
          menu: _menu,
          canDelete: WaiterAuth.instance.can(WaiterPermissions.cancelOrders),
        ),
      ),
    );
    if (changed == true) {
      await _loadOrders();
    }
  }

  /// Deletes an unpaid order (with confirmation) before it is closed.
  Future<void> _deleteOrder(Order order) async {
    if (!WaiterAuth.instance.can(WaiterPermissions.cancelOrders)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to delete orders.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Order #${order.id}?'),
        content: Text(
            'This will permanently remove the unpaid order for table '
            '${order.tableNumber} (${order.itemCount} items, '
            '${formatKyat(order.total)}). This cannot be undone.'),
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
      await AppConfig.instance.api.deleteOrder(order.id!);
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #${order.id} deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete order: $e')),
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
    final canCancelOrders = auth.can(WaiterPermissions.cancelOrders);

    // Bottom navigation items: Tables, Menu, Orders and Parcel.
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
        icon: Icon(Icons.table_restaurant_outlined),
        activeIcon: Icon(Icons.table_restaurant),
        label: 'Tables',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.restaurant_menu_outlined),
        activeIcon: Icon(Icons.restaurant_menu),
        label: 'Menu',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.receipt_long_outlined),
        activeIcon: Icon(Icons.receipt_long),
        label: 'Orders',
      ),
      const BottomNavigationBarItem(
        icon: Icon(Icons.shopping_bag_outlined),
        activeIcon: Icon(Icons.shopping_bag),
        label: 'Parcel',
      ),
    ];

    // Keep the index in range.
    if (_currentIndex >= items.length) _currentIndex = 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.isLoggedIn ? auth.displayNameOrUsername : 'Waiter'),
        actions: [
          if (_selectedTable != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Chip(
                avatar: const Icon(Icons.table_restaurant, size: 16),
                label: Text('Table $_selectedTable'),
                visualDensity: VisualDensity.compact,
              ),
            ),
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
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            _ipBar(),
            if (_error != null) _errorView(),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: [
                  _tablesView(context, bp),
                  _menuView(context, bp),
                  _ordersView(context, canCancelOrders),
                  _menuView(context, bp, parcel: true),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 0 || index == 2) {
            _loadOrders(silent: true);
          }
        },
        items: items,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.success, // green active tab
        unselectedItemColor: const Color(0xFF1A237E), // dark blue inactive
        selectedLabelStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
      ),
    );
  }

  /// Grid of tables. Occupied tables (active order) are highlighted and show
  /// their order status; tapping an occupied table opens its order sheet.
  Widget _tablesView(BuildContext context, Breakpoint bp) {
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ResponsiveGrid(
        compact: 3,
        medium: 4,
        expanded: 6,
        large: 8,
        childAspectRatio: 1.0,
        itemCount: _tableCount,
        itemBuilder: (context, i) {
          final table = 'T${i + 1}';
          final activeOrder = _activeOrderFor(table);
          final isSelected = _selectedTable == table;
          final isOccupied = activeOrder != null;
          final canTakeOrders =
              WaiterAuth.instance.can(WaiterPermissions.takeOrders);
          final canViewOrders =
              WaiterAuth.instance.can(WaiterPermissions.viewOrders);
          return _tableCard(
            table: table,
            isSelected: isSelected,
            isOccupied: isOccupied,
            status: activeOrder?.status,
            orderTotal: activeOrder?.total,
            onTap: (canTakeOrders || canViewOrders)
                ? () {
                    if (isOccupied) {
                      if (canViewOrders) {
                        _showTableOrderSheet(table);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text('Table $table has an active order.')),
                        );
                      }
                      return;
                    }
                    if (!canTakeOrders) return;
                    setState(() {
                      _selectedTable = table;
                      _currentIndex = 1; // jump to Menu
                    });
                  }
                : null,
          );
        },
      ),
    );
  }

  /// Opens a bottom sheet listing the orders placed at [table], with each
  /// order's line items and the payment (total) breakdown.
  void _showTableOrderSheet(String table) {
    final tableOrders = _orders.where((o) => o.tableNumber == table).toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));
    if (tableOrders.isEmpty) return;
    final canCancelOrders =
        WaiterAuth.instance.can(WaiterPermissions.cancelOrders);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.table_restaurant,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('Table $table — Orders & Payment',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: tableOrders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _tableOrderCard(tableOrders[i], canCancelOrders),
                ),
              ),
              if (WaiterAuth.instance.can(WaiterPermissions.takeOrders)) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: Text('Table $table သို့ ပစ္စည်းထပ်မှာရန် (Add Items)'),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        setState(() {
                          _selectedTable = table;
                          _isParcelMode = false;
                          _currentIndex = 1; // jump to Menu
                        });
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Opens the guided Bluetooth printer workflow (scan -> connect -> print)
  /// for [order]'s payment receipt.
  /// Opens the voucher/bill preview, fetching shop settings from the Admin
  /// Host (shop name/address + Gov Tax %).
  Future<void> _openVoucher(Order order) async {
    try {
      final settings = await AppConfig.instance.api.fetchShopSettings();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => VoucherScreen(order: order, settings: settings),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load shop settings: $e')),
      );
    }
  }

  void _printReceipt(Order order) {
    showDialog<void>(
      context: context,
      builder: (_) => PrinterDialog(
        printer: BluetoothPrinterService.instance,
        order: order,
      ),
    );
  }

  /// One order inside the table sheet: header, line items and payment summary.
  Widget _tableOrderCard(Order order, bool canCancelOrders) {
    final canCancel = canCancelOrders &&
        order.status != AppConstants.statusServed &&
        order.status != AppConstants.statusCancelled;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text('#${order.id}',
                      style: const TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.createdAt != null
                        ? AppConfig.instance.dateFormat.format(order.createdAt!)
                        : '--:--',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ),
                statusChip(order.status),
              ],
            ),
            const Divider(height: 16),
            if (order.items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No items recorded.',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              )
            else
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('${item.quantity} × ${item.name}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                      Text(formatMoney(item.subtotal),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text('${order.itemCount} items',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ),
                const Text('Payment: ',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600)),
                Text(formatMoney(order.total),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 4,
                  children: [
                    if (WaiterAuth.instance.can(WaiterPermissions.takeOrders))
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _editOrder(order);
                        },
                        icon: const Icon(Icons.edit_outlined,
                            color: AppColors.primary),
                        label: const Text('Edit',
                            style: TextStyle(color: AppColors.primary)),
                      ),
                    if (canCancel)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _deleteOrder(order);
                        },
                        icon: const Icon(Icons.delete_outline,
                            color: AppColors.error),
                        label: const Text('Delete',
                            style: TextStyle(color: AppColors.error)),
                      ),
                    TextButton.icon(
                      onPressed: () => _openVoucher(order),
                      icon: const Icon(Icons.receipt_long_outlined,
                          color: AppColors.primary),
                      label: const Text('Voucher',
                          style: TextStyle(color: AppColors.primary)),
                    ),
                    TextButton.icon(
                      onPressed: () => _printReceipt(order),
                      icon: const Icon(Icons.print,
                          color: AppColors.primary),
                      label: const Text('Print Receipt',
                          style: TextStyle(color: AppColors.primary)),
                    ),
                    if (canCancel)
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _cancelOrder(order);
                        },
                        icon: const Icon(Icons.cancel_outlined,
                            color: AppColors.error),
                        label: const Text('Cancel',
                            style: TextStyle(color: AppColors.error)),
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

  /// Orders tab: list of ACTIVE unpaid orders. Tapping a card opens the
  /// full-screen Edit Order screen; the expand icon toggles item details.
  Widget _ordersView(BuildContext context, bool canCancelOrders) {
    if (_ordersLoading && _orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final orders = _orders;
    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 80),
                Icon(Icons.receipt_long_outlined,
                    size: 64, color: AppColors.muted),
                SizedBox(height: 16),
                Center(
                    child: Text('No active orders',
                        style: TextStyle(color: AppColors.muted))),
                SizedBox(height: 8),
                Center(
                    child: Text('All unpaid orders will appear here',
                        style: TextStyle(
                            color: AppColors.muted, fontSize: 12))),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: orders.length,
              itemBuilder: (context, i) {
                final order = orders[i];
                final isExpanded = _expandedOrderId == order.id;
                final canCancel = canCancelOrders &&
                    order.status != AppConstants.statusServed &&
                    order.status != AppConstants.statusCancelled;
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      // Tappable header -> full-screen Edit Order screen.
                      InkWell(
                        onTap: () => _editOrder(order),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor:
                                    AppColors.primary.withOpacity(0.1),
                                child: Text('#${order.id}',
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.tableNumber,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      order.createdAt != null
                                          ? AppConfig.instance.dateFormat
                                              .format(order.createdAt!)
                                          : '--:--',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatMoney(order.total),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.success)),
                                  Text('${order.itemCount} items',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted)),
                                ],
                              ),
                              const SizedBox(width: 8),
                              statusChip(order.status),
                              const SizedBox(width: 4),
                              // Expand/collapse item details.
                              IconButton(
                                icon: Icon(
                                  isExpanded
                                      ? Icons.expand_less
                                      : Icons.expand_more,
                                  color: AppColors.muted,
                                ),
                                onPressed: () => _toggleOrderExpanded(order),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            children: [
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              for (final item in order.items)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                            '${item.quantity} × ${item.name}',
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ),
                                      Text(formatMoney(item.subtotal),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (canCancel)
                                    TextButton.icon(
                                      onPressed: () => _deleteOrder(order),
                                      icon: const Icon(Icons.delete_outline,
                                          color: AppColors.error),
                                      label: const Text('Delete',
                                          style: TextStyle(
                                              color: AppColors.error)),
                                    ),
                                  TextButton.icon(
                                    onPressed: () => _openVoucher(order),
                                    icon: const Icon(
                                        Icons.receipt_long_outlined,
                                        color: AppColors.primary),
                                    label: const Text('Voucher',
                                        style: TextStyle(
                                            color: AppColors.primary)),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _printReceipt(order),
                                    icon: const Icon(Icons.print,
                                        color: AppColors.primary),
                                    label: const Text('Print Receipt',
                                        style: TextStyle(
                                            color: AppColors.primary)),
                                  ),
                                  if (canCancel)
                                    TextButton.icon(
                                      onPressed: () => _cancelOrder(order),
                                      icon: const Icon(Icons.cancel_outlined,
                                          color: AppColors.error),
                                      label: const Text('Cancel',
                                          style: TextStyle(
                                              color: AppColors.error)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  /// Menu tab (also reused for Parcel). Shows categories and menu items with
  /// add-to-cart buttons; when a table is selected the cart bar is shown.
  Widget _menuView(BuildContext context, Breakpoint bp, {bool parcel = false}) {
    if (_menuLoading && _menu.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_menu.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No menu items yet.',
                style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadMenu, child: const Text('Retry')),
          ],
        ),
      );
    }

    final grouped = _filteredGroupedMenu;
    final categories = grouped.keys.toList();
    final allCategoryList = _groupedMenu.keys.toList()..sort();
    final isAllSelected = _selectedCategory.isEmpty ||
        _selectedCategory.toLowerCase() == 'all';

    return Column(
      children: [
        // Instant search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ပစ္စည်းများ ရှာဖွေရန် (Search items...)',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),

        // Category chips
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              ChoiceChip(
                label: Text('All (${_menu.length})'),
                selected: isAllSelected,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: isAllSelected ? Colors.white : AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                onSelected: (_) {
                  setState(() => _selectedCategory = 'All');
                },
              ),
              const SizedBox(width: 8),
              for (final cat in allCategoryList)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$cat (${_groupedMenu[cat]?.length ?? 0})'),
                    selected: !isAllSelected &&
                        _selectedCategory.trim().toLowerCase() ==
                            cat.trim().toLowerCase(),
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: (!isAllSelected &&
                              _selectedCategory.trim().toLowerCase() ==
                                  cat.trim().toLowerCase())
                          ? Colors.white
                          : AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = selected ? cat : 'All';
                      });
                    },
                  ),
                ),
            ],
          ),
        ),

        // Menu items list
        Expanded(
          child: _menuLoading
              ? const Center(child: CircularProgressIndicator())
              : categories.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search_off,
                              size: 48, color: AppColors.muted),
                          const SizedBox(height: 8),
                          Text(
                            _searchController.text.trim().isNotEmpty
                                ? 'No items match "${_searchController.text.trim()}"'
                                : 'No items in this category.',
                            style: const TextStyle(
                                color: AppColors.muted, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                      itemCount: categories.length,
                      itemBuilder: (context, i) {
                        final cat = categories[i];
                        final items = grouped[cat] ?? const [];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                              child: Text(
                                cat,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            for (final item in items) _menuRow(item),
                          ],
                        );
                      },
                    ),
        ),
      ],
    );
  }

  /// Single compact menu row: thumbnail, name, Kyat price, in-cart badge,
  /// and add button cleanly aligned on a single horizontal row.
  Widget _menuRow(MenuItem item) {
    final inCart = _cart[item.id]?.quantity ?? 0;
    return InkWell(
      onTap: () => _addToCart(item),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  item.imageUrl!,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.fastfood,
                      size: 40, color: AppColors.muted),
                ),
              )
            else
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fastfood_outlined,
                    size: 24, color: AppColors.primary),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.style(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatKyat(item.price),
                    style: AppFonts.style(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (inCart > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'x$inCart',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                onPressed: () => _addToCart(item),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                tooltip: 'Add to order',
                icon: const Icon(Icons.add_circle,
                    size: 28, color: AppColors.success),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A single table tile in the tables grid.
  Widget _tableCard({
    required String table,
    required bool isSelected,
    required bool isOccupied,
    String? status,
    double? orderTotal,
    VoidCallback? onTap,
  }) {
    final statusColor = status == null
        ? Colors.transparent
        : status == AppConstants.statusReady
            ? AppColors.success
            : status == AppConstants.statusPreparing
                ? Colors.orange
                : AppColors.primary;
    return Card(
      color: isSelected
          ? AppColors.primary.withOpacity(0.08)
          : isOccupied
              ? statusColor.withOpacity(0.08)
              : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? AppColors.primary
              : isOccupied
                  ? statusColor
                  : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isOccupied
                    ? Icons.table_bar
                    : Icons.table_restaurant_outlined,
                size: 28,
                color: isOccupied ? statusColor : AppColors.muted,
              ),
              const SizedBox(height: 4),
              Text(table,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (isOccupied && orderTotal != null)
                Text(formatMoney(orderTotal),
                    style: TextStyle(fontSize: 11, color: statusColor)),
              if (isOccupied && status != null)
                Text(status,
                    style: TextStyle(fontSize: 10, color: statusColor)),
            ],
          ),
        ),
      ),
    );
  }

  /// Small bar showing the Admin Host address and connection state.
  Widget _ipBar() {
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: AppColors.primary.withOpacity(0.05),
        child: Row(
          children: [
            Icon(
              _error == null ? Icons.cloud_done : Icons.cloud_off,
              size: 16,
              color: _error == null ? AppColors.success : AppColors.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Host: ${AppConfig.instance.baseUrl}',
                style: const TextStyle(fontSize: 11, color: AppColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: _connect,
              child: const Text('Change', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
    );
  }

  /// Inline error banner shown when the Admin Host is unreachable.
  Widget _errorView() {
    return Material(
      color: AppColors.error.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _error ?? '',
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() => _error = null);
                _connect();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
