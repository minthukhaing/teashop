library teashop_pos.presentation.role_selection_screen;

import 'package:flutter/material.dart';

import 'admin/admin_login_screen.dart';
import 'app_mode.dart';
import 'app_theme.dart';
import 'kitchen/kitchen_shell.dart';
import 'responsive_helpers.dart';
import 'waiter/waiter_login_screen.dart';

/// Runtime role picker shown when the app is not launched with a `--dart-define`.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Teashop POS')),
      body: GradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bp = breakpointOf(constraints.maxWidth);
              final columns = bp.isCompact ? 1 : (bp.isMedium ? 2 : 3);
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: bp.isLarge ? 1100 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _header(),
                        const SizedBox(height: 28),
                        GridView.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: bp.isCompact ? 2.0 : 1.8,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _roleCard(
                              context,
                              'Admin Host',
                              'Embedded SQLite DB + live HTTP server on :8080',
                              Icons.computer,
                              AppColors.primary,
                              AppMode.admin,
                            ),
                            _roleCard(
                              context,
                              'Waiter',
                              'Browse the menu and send orders to the kitchen',
                              Icons.point_of_sale,
                              AppColors.accent,
                              AppMode.waiter,
                            ),
                            _roleCard(
                              context,
                              'Kitchen Display',
                              'View incoming orders and advance each step',
                              Icons.restaurant,
                              AppColors.success,
                              AppMode.kitchen,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _footer(),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.local_cafe, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 16),
        const Text(
          'Welcome',
          style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.onSurface),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose your role to continue',
          style: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
      ],
    );
  }

  Widget _footer() {
    return const Text(
      'Local network POS  •  v1.0.0',
      style: TextStyle(fontSize: 12, color: AppColors.muted),
    );
  }

  Widget _roleCard(
    BuildContext context,
    String title,
    String sub,
    IconData icon,
    Color color,
    AppMode role,
  ) {
    return GlassCard(
      tint: color,
      opacity: 0.12,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _pick(context, role),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (role == AppMode.admin || role == AppMode.waiter)
                  Icon(Icons.lock_outline, size: 16, color: color.withOpacity(0.7)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sub,
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Icon(Icons.arrow_forward, color: color),
            ),
          ],
        ),
      ),
    );
  }

  void _pick(BuildContext context, AppMode role) {
    final Widget home = switch (role) {
      AppMode.admin => const AdminLoginScreen(),
      AppMode.waiter => const WaiterLoginScreen(),
      AppMode.kitchen => const KitchenShell(),
    };
    // Admin and Waiter go through a login screen first; push (not replace) so
    // the user can navigate back to role selection. Kitchen replaces immediately.
    if (role == AppMode.admin || role == AppMode.waiter) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => home));
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => home),
      );
    }
  }
}
