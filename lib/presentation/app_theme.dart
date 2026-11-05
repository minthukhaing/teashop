library teashop_pos.presentation.app_theme;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────── Color Palettes ───────────────────────────────────

/// Teashop-inspired color palette.
class AppColors {
  AppColors._();
  static const Color primary = Color(0xFF5D4037);      // dark coffee brown
  static const Color primaryDark = Color(0xFF3E2723);
  static const Color accent = Color(0xFF8D6E63);
  static const Color surfaceCream = Color(0xFFF5F0EA);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFC62828);
  static const Color onSurface = Color(0xFF212121);
  static const Color muted = Color(0xFF757575);
}

/// Admin role dark-green sidebar colour palette.
class AdminColors {
  AdminColors._();
  static const Color sidebarBg = Color(0xFF1B3A1E);
  static const Color sidebarSelected = Color(0xFF2D5A32);
  static const Color sidebarText = Colors.white;
  static const Color sidebarMuted = Color(0xFFB0C4B1);
  static const Color sidebarHeader = Color(0xFF143016);
}

// ─────────────────────────── Myanmar Font Helper ──────────────────────────────

/// Myanmar Unicode font – Noto Sans Myanmar from Google Fonts.
/// Use [AppFonts.myanmar] as the [fontFamily] in [TextStyle]s, or rely on
/// [appTheme] which applies it globally via [ThemeData.textTheme].
class AppFonts {
  AppFonts._();

  /// Returns a [TextTheme] where every style uses Noto Sans Myanmar,
  /// merged on top of the base theme's text styles.
  static TextTheme myanmarTextTheme([TextTheme? base]) =>
      GoogleFonts.notoSansMyanmarTextTheme(base);

  /// Single [TextStyle] with Noto Sans Myanmar – handy for one-off overrides.
  static TextStyle style({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.notoSansMyanmar(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
}

// ─────────────────────────── App Theme ───────────────────────────────────────

/// Full [ThemeData] for the Teashop POS app with Noto Sans Myanmar applied
/// globally so every [Text] widget renders Myanmar glyphs correctly.
ThemeData appTheme() {
  // Build the base colour scheme first.
  final cs = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    primary: AppColors.primary,
    secondary: AppColors.accent,
    surface: AppColors.surfaceCream,
    error: AppColors.error,
  );

  // Merge Myanmar font into the Material text theme.
  final baseTextTheme = ThemeData(colorScheme: cs).textTheme;
  final myanmarTextTheme = AppFonts.myanmarTextTheme(baseTextTheme);

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,

    // ── Global Myanmar font ─────────────────────────────────────────────────
    textTheme: myanmarTextTheme,
    primaryTextTheme: AppFonts.myanmarTextTheme(
        ThemeData(colorScheme: cs).primaryTextTheme),

    // ── App Bar ─────────────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      titleTextStyle: AppFonts.style(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),

    // ── Elevated Button ─────────────────────────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppFonts.style(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // ── Text Button ─────────────────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),

    // ── Outlined Button ─────────────────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: AppFonts.style(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),

    // ── Card ────────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),

    // ── Input / TextField ───────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      labelStyle: AppFonts.style(fontSize: 14, color: AppColors.muted),
      hintStyle: AppFonts.style(fontSize: 14, color: AppColors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    ),

    // ── Bottom Navigation Bar ───────────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.all(
        AppFonts.style(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),

    // ── Chip ────────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      labelStyle: AppFonts.style(fontSize: 12),
    ),

    // ── Snack Bar ───────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      contentTextStyle: AppFonts.style(fontSize: 14, color: Colors.white),
    ),

    // ── Dialog ──────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      titleTextStyle: AppFonts.style(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.onSurface,
      ),
      contentTextStyle: AppFonts.style(
        fontSize: 14,
        color: AppColors.muted,
      ),
    ),
  );
}

// ─────────────────────────── Utility ─────────────────────────────────────────

/// Formats a monetary amount in Kyat for display.  e.g. "K 5,000"
String formatMoney(double amount) {
  final rounded = amount.round();
  // Simple thousands separator
  final str = rounded.toString();
  final buffer = StringBuffer();
  int count = 0;
  for (int i = str.length - 1; i >= 0; i--) {
    if (count > 0 && count % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
    count++;
  }
  return 'K ${buffer.toString().split('').reversed.join()}';
}
