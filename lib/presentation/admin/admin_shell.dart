library teashop_pos.presentation.admin.admin_shell;

import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/local_ip.dart';
import '../../../data/database/app_database.dart';
import '../../../server/app_server.dart';
import '../app_theme.dart';
import 'admin_dashboard.dart';
import 'admin_menu_management.dart' show MenuManagementScreen;
import 'admin_staff_management.dart';
import 'admin_login_screen.dart';
import '../../../core/auth/admin_auth.dart';
import 'screens/admin_counter_screen.dart';
import 'screens/admin_categories_screen.dart';
import 'screens/admin_tables_screen.dart';
import 'screens/admin_payment_methods_screen.dart';
import 'screens/admin_expenses_screen.dart';
import 'screens/admin_reports_screen.dart';
import 'screens/admin_income_expense_screen.dart';

// ──────────────────────────── Nav item model ─────────────────────────────────
class _NavItem {
  const _NavItem({
    required this.label,
    required this.emoji,
    required this.icon,
    required this.widget,
  });
  final String label;
  final String emoji;
  final IconData icon;
  final Widget widget;
}

// ──────────────────────────── AdminShell ─────────────────────────────────────
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final AppDatabase _db = AppDatabase.instance;
  late final AppServer _server;
  bool _serverRunning = false;
  String _serverStatus = 'Starting…';
  int _selectedIndex = 0;
  String _localIp = 'Resolving…';

  // ── All navigation destinations ──────────────────────────────────────────
  static const List<_NavItem> _navItems = [
    _NavItem(
      label: 'Dashboard',
      emoji: '📊',
      icon: Icons.dashboard_outlined,
      widget: AdminDashboard(),
    ),
    _NavItem(
      label: 'Counter',
      emoji: '🖥️',
      icon: Icons.computer_outlined,
      widget: AdminCounterScreen(),
    ),
    _NavItem(
      label: 'Kitchen',
      emoji: '👨‍🍳',
      icon: Icons.kitchen_outlined,
      widget: _KitchenPlaceholder(),
    ),
    _NavItem(
      label: 'Menu',
      emoji: '📋',
      icon: Icons.menu_book_outlined,
      widget: MenuManagementScreen(),
    ),    _NavItem(
      label: 'Categories',
      emoji: '📁',
      icon: Icons.folder_outlined,
      widget: AdminCategoriesScreen(),
    ),
    _NavItem(
      label: 'Tables',
      emoji: '🪑',
      icon: Icons.table_restaurant_outlined,
      widget: AdminTablesScreen(),
    ),
    _NavItem(
      label: 'Payment Methods',
      emoji: '💳',
      icon: Icons.payment_outlined,
      widget: AdminPaymentMethodsScreen(),
    ),
    _NavItem(
      label: 'ထွက်ငွေ',
      emoji: '✍️',
      icon: Icons.arrow_circle_up_outlined,
      widget: AdminExpensesScreen(),
    ),
    _NavItem(
      label: 'Reports',
      emoji: '📈',
      icon: Icons.bar_chart_outlined,
      widget: AdminReportsScreen(),
    ),
    _NavItem(
      label: 'ဝင်ငွေ / ထွက်ငွေ',
      emoji: '💰',
      icon: Icons.account_balance_wallet_outlined,
      widget: AdminIncomeExpenseScreen(),
    ),
    _NavItem(
      label: 'Staff',
      emoji: '👥',
      icon: Icons.people_outline,
      widget: AdminStaffManagementScreen(),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _server = AppServer.withDb(_db);
    _startServer();
    _resolveIp();
  }

  Future<void> _startServer() async {
    try {
      await _server.start();
      if (!mounted) return;
      setState(() {
        _serverRunning = true;
        _serverStatus = 'Port :${AppConstants.serverPort}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _serverStatus = 'Error: $e');
    }
  }

  Future<void> _resolveIp() async {
    final ip = await LocalIpResolver.getLocalIpAddress();
    if (!mounted) return;
    setState(() => _localIp = ip ?? '127.0.0.1');
  }

  void _logout() {
    _server.stop();
    AdminAuth.instance.logout();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
    );
  }

  @override
  void dispose() {
    _server.stop();
    super.dispose();
  }

  void _selectItem(int index) {
    setState(() => _selectedIndex = index);
    Navigator.of(context).pop(); // close drawer
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = _navItems[_selectedIndex];

    return Scaffold(
      backgroundColor: AppColors.surfaceCream,
      // ── App bar ───────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: AdminColors.sidebarBg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Text(
          currentItem.label,
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        actions: [
          // Server status badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: _serverRunning
                  ? Colors.green.shade600
                  : Colors.red.shade700,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _serverRunning ? 'ONLINE' : 'OFFLINE',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock_reset_outlined, color: Colors.white),
            tooltip: 'Change Password',
            onPressed: _showChangePasswordDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: 'Logout',
            onPressed: _logout,
          ),
        ],
      ),

      // ── Drawer (Sidebar) ──────────────────────────────────────────────────
      drawer: Drawer(
        width: 285,
        backgroundColor: AdminColors.sidebarBg,
        child: SafeArea(
          child: Column(
            children: [
              // Header
              _buildDrawerHeader(),
              // Status bar
              _buildStatusBar(),
              const SizedBox(height: 8),
              // Nav items
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  itemCount: _navItems.length,
                  itemBuilder: (context, index) =>
                      _buildNavTile(index),
                ),
              ),
              // Bottom: change password + logout
              _buildDrawerFooter(),
            ],
          ),
        ),
      ),

      // ── Body ──────────────────────────────────────────────────────────────
      body: IndexedStack(
        index: _selectedIndex,
        children: _navItems.map((e) => e.widget).toList(),
      ),
    );
  }

  // ─────────────────────────── Drawer widgets ──────────────────────────────

  Widget _buildDrawerHeader() {
    return Container(
      color: AdminColors.sidebarHeader,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Row(
        children: [
          // Tea cup icon in a circle
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🍵', style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tea Shop',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.shade500,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Drawer close button (◄ Hide style)
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: Colors.white, size: 18),
                  Text('Hide',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Admin avatar
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.green.shade500,
            child: const Text('a',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                Text('$_localIp  •  $_serverStatus',
                    style: const TextStyle(
                        color: AdminColors.sidebarMuted, fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
              ],
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _serverRunning ? Colors.green.shade400 : Colors.red,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(int index) {
    final item = _navItems[index];
    final selected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _selectItem(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AdminColors.sidebarSelected
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Emoji icon
            Text(item.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: selected ? Colors.white : AdminColors.sidebarMuted,
                  fontSize: 15,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          // Change password
          _footerButton(
            icon: Icons.lock_reset_outlined,
            label: 'Change Password',
            onTap: () {
              Navigator.pop(context);
              _showChangePasswordDialog();
            },
          ),
          const SizedBox(height: 4),
          // Logout
          _footerButton(
            icon: Icons.logout,
            label: 'Logout',
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? Colors.red.shade300 : AdminColors.sidebarMuted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: color, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────── Change password dialog ─────────────────────────

  Future<void> _showChangePasswordDialog() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    String? error;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'Current password',
                    suffixIcon: IconButton(
                      icon: Icon(obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 4 characters',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminColors.sidebarBg,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (newCtrl.text.length < 4) {
                  setState(() =>
                      error = 'New password must be at least 4 characters.');
                  return;
                }
                if (newCtrl.text != confirmCtrl.text) {
                  setState(() => error = 'Passwords do not match.');
                  return;
                }
                final success = await AdminAuth.instance
                    .changePassword(oldCtrl.text, newCtrl.text);
                if (!context.mounted) return;
                if (success) {
                  Navigator.pop(context, true);
                } else {
                  setState(() => error = 'Current password is incorrect.');
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    oldCtrl.dispose();
    newCtrl.dispose();
    confirmCtrl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password updated.')),
      );
    }
  }
}

// ──────────────────────── Kitchen placeholder ────────────────────────────────
/// Placeholder widget — links through to the KDS in a real production build.
class _KitchenPlaceholder extends StatelessWidget {
  const _KitchenPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('👨‍🍳', style: TextStyle(fontSize: 64)),
          SizedBox(height: 16),
          Text('Kitchen Display',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Kitchen မှ KDS app ကို ဖွင့်ပါ',
              style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

}
