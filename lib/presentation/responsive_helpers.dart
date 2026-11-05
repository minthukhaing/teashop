library teashop_pos.presentation.responsive_helpers;

import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Material 3-inspired window-size breakpoints.
///
/// Mirrors the official Flutter window-size classes so every screen adapts
/// consistently across phones, tablets and desktop/admin displays.
enum Breakpoint {
  /// Phones in portrait (< 600 dp).
  compact,
  /// Small tablets / large phones (600–839 dp).
  medium,
  /// Tablets in landscape / small desktops (840–1199 dp).
  expanded,
  /// Desktops / admin displays (>= 1200 dp).
  large,
}

extension BreakpointExtensions on Breakpoint {
  bool get isCompact => this == Breakpoint.compact;
  bool get isMedium => this == Breakpoint.medium;
  bool get isExpanded => this == Breakpoint.expanded;
  bool get isLarge => this == Breakpoint.large;

  /// Wide enough to replace the bottom bar with a navigation rail.
  bool get useNavigationRail => index >= Breakpoint.expanded.index;
}

/// Resolves a [Breakpoint] from a raw width in logical pixels.
Breakpoint breakpointOf(double width) {
  if (width < 600) return Breakpoint.compact;
  if (width < 840) return Breakpoint.medium;
  if (width < 1200) return Breakpoint.expanded;
  return Breakpoint.large;
}

/// Convenience wrapper around [MediaQuery.sizeOf].
Breakpoint breakpointOfContext(BuildContext context) =>
    breakpointOf(MediaQuery.sizeOf(context).width);

/// Adaptive grid column count.
///
/// Each breakpoint can be tuned independently so a menu can show two columns on
/// a phone while the KDS shows four on a wide kitchen monitor.
int gridColumnsForWidth(
  double width, {
  int compact = 1,
  int medium = 2,
  int expanded = 3,
  int large = 4,
}) {
  switch (breakpointOf(width)) {
    case Breakpoint.compact:
      return compact;
    case Breakpoint.medium:
      return medium;
    case Breakpoint.expanded:
      return expanded;
    case Breakpoint.large:
      return large;
  }
}

/// A responsive grid that picks its cross-axis count from the available width.
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.compact = 1,
    this.medium = 2,
    this.expanded = 3,
    this.large = 4,
    this.mainAxisSpacing = 12,
    this.crossAxisSpacing = 12,
    this.childAspectRatio = 1,
    this.shrinkWrap = false,
    this.padding,
  });

  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final int compact;
  final int medium;
  final int expanded;
  final int large;
  final double mainAxisSpacing;
  final double crossAxisSpacing;
  final double childAspectRatio;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = gridColumnsForWidth(
          constraints.maxWidth,
          compact: compact,
          medium: medium,
          expanded: expanded,
          large: large,
        );
        return GridView.builder(
          padding: padding,
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );
      },
    );
  }
}

/// A frosted-glass card built on [BackdropFilter].
///
/// Looks best when placed over a gradient or image background. Over a solid
/// colour it still renders a clean, translucent, bordered surface.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 14,
    this.opacity = 0.18,
    this.tint,
    this.radius = 18,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.elevation = 0,
  });

  final Widget child;
  final double blur;
  final double opacity;
  final Color? tint;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Border? border;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final surface = tint ?? Colors.white;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surface.withOpacity(opacity),
            borderRadius: BorderRadius.circular(radius),
            border: border ??
                Border.all(color: Colors.white.withOpacity(0.25), width: 1),
            boxShadow: elevation > 0
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: elevation,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// A soft diagonal gradient used as a screen backdrop so [GlassCard] surfaces
/// have something interesting to blur.
class GradientBackground extends StatelessWidget {
  const GradientBackground({
    super.key,
    required this.child,
    this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });

  final Widget child;
  final List<Color>? colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  @override
  Widget build(BuildContext context) {
    final palette =
        colors ?? [AppColors.surfaceCream, const Color(0xFFECE0D5)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: begin, end: end, colors: palette),
      ),
      child: child,
    );
  }
}

/// Status → colour mapping shared by every screen.
Color statusColor(String status) => switch (status) {
      'pending' => AppColors.warning,
      'preparing' => AppColors.accent,
      'ready' => AppColors.success,
      'served' => Colors.teal,
      'cancelled' => AppColors.error,
      _ => AppColors.muted,
    };
