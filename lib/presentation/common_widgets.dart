library teashop_pos.presentation.common_widgets;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Styled text input with a label and optional prefix icon.
Widget appTextField({
  required BuildContext context,
  required String label,
  String? hint,
  TextEditingController? controller,
  TextInputType? keyboardType,
  IconData? prefixIcon,
  bool obscureText = false,
  int maxLines = 1,
  String? Function(String?)? validator,
  ValueChanged<String>? onChanged,
}) {
  return TextFormField(
    controller: controller,
    keyboardType: keyboardType,
    obscureText: obscureText,
    maxLines: maxLines,
    validator: validator,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
    ),
  );
}

/// Primary action button.
Widget appButton({
  required String label,
  VoidCallback? onPressed,
  bool loading = false,
  Color? backgroundColor,
}) {
  return SizedBox(
    height: 50,
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );
}

/// Outlined secondary button.
Widget appOutlineButton({
  required String label,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    height: 50,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    ),
  );
}

/// Section heading used across screens.
Widget sectionTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 20,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
        ),
      ],
    ),
  );
}

/// A small status chip with a color matched to the order status.
Widget statusChip(String status) {
  final Color color = switch (status) {
    'pending' => AppColors.warning,
    'preparing' => AppColors.accent,
    'ready' => AppColors.success,
    'served' => Colors.teal,
    'cancelled' => AppColors.error,
    _ => AppColors.muted,
  };
  final String label = switch (status) {
    'pending' => 'Pending',
    'preparing' => 'Preparing',
    'ready' => 'Ready',
    'served' => 'Served',
    'cancelled' => 'Cancelled',
    _ => status,
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.5)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
