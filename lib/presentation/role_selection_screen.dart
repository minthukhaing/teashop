library teashop_pos.presentation.role_selection_screen;

import 'package:flutter/material.dart';

import 'admin/admin_login_screen.dart';
import 'app_mode.dart';
import 'app_theme.dart';
import 'kitchen/kitchen_shell.dart';
import 'responsive_helpers.dart';
import 'waiter/waiter_login_screen.dart';

/// Runtime role picker shown when the app is not launched with a `--dart-define`.
///
/// Mobile-first redesign:
/// - No AppBar; the brand identity lives in a hero header inside the body.
/// - Role cards are full-width, >= 88dp tall touch targets on compact screens
///   and flow into a 2-column grid on medium+ breakpoints.
/// - Cards use elevated glass surfaces with a coloured tint, soft shadow and
///   animated press feedback (scale + ripple) so taps feel responsive.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final bp = breakpointOf(constraints.maxWidth);
              final columns = bp.isCompact ? 1 : 2;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: bp.isLarge ? 1100 : double.infinity,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: bp.isCompact ? 20 : 32,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _BrandHeader(),
                        SizedBox(height: bp.isCompact ? 32 : 40),
                        GridView.count(
                          crossAxisCount: columns,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: bp.isCompact ? 1.55 : 1.5,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _RoleCard(
                              title: 'Admin Host',
                              description:
                                  'Embedded SQLite DB + live HTTP server on :8080',
                              icon: Icons.computer,
                              color: AppColors.primary,
                              role: AppMode.admin,
                            ),
                            _RoleCard(
                              title: 'Waiter',
                              description:
                                  'Browse the menu and send orders to the kitchen',
                              icon: Icons.point_of_sale,
                              color: AppColors.accent,
                              role: AppMode.waiter,
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),
                        const _Footer(),
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
}

// ───────────────────────────── Brand header ──────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo chip.
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.local_cafe, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 24),
        // Brand eyebrow label.
        Text(
          'TEASHOP POS',
          textAlign: TextAlign.center,
          style: AppFonts.style(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome',
          textAlign: TextAlign.center,
          style: AppFonts.style(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose your role to continue',
          textAlign: TextAlign.center,
          style: AppFonts.style(
            fontSize: 15,
            color: AppColors.muted,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── Role card ─────────────────────────────────────

/// A single tappable role card with press-scale and ripple feedback.
class _RoleCard extends StatefulWidget {
  const _RoleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.role,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final AppMode role;

  @override
  State<_RoleCard> createState() => _RoleCardState();
}

class _RoleCardState extends State<_RoleCard> {
  bool _pressed = false;

  void _setPressed(bool value) => setState(() => _pressed = value);

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: _pressed ? 0.30 : 0.18),
              blurRadius: _pressed ? 10 : 20,
              offset: Offset(0, _pressed ? 2 : 8),
            ),
          ],
        ),
        child: GlassCard(
          tint: Colors.white,
          opacity: 0.85,
          radius: 22,
          padding: const EdgeInsets.all(20),
          border: Border.all(color: color.withValues(alpha: _pressed ? 0.55 : 0.25)),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            splashColor: color.withValues(alpha: 0.12),
            highlightColor: color.withValues(alpha: 0.08),
            onTapDown: (_) => _setPressed(true),
            onTapCancel: () => _setPressed(false),
            onTap: () {
              _setPressed(false);
              _pick(context, widget.role);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon container: rounded square with tinted fill.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.25)),
                  ),
                  child: Icon(widget.icon, color: color, size: 26),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.style(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                // Continue affordance row.
                Row(
                  children: [
                    Text(
                      'Continue',
                      style: AppFonts.style(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, color: color, size: 18),
                  ],
                ),
              ],
            ),
          ),
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

// ───────────────────────────── Footer ────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Local network POS - v1.0.0',
      textAlign: TextAlign.center,
      style: AppFonts.style(fontSize: 12, color: AppColors.muted),
    );
  }
}
