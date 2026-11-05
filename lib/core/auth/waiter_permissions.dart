library teashop_pos.core.auth.waiter_permissions;

import 'dart:convert';

/// Fine-grained capabilities a waiter can be granted by the admin.
///
/// Stored on the Admin Host as a JSON array string in the `users.permissions`
/// column and handed to the waiter client on a successful login so the UI can
/// gate actions locally.
class WaiterPermissions {
  WaiterPermissions._();

  /// Permission key constants.
  static const String takeOrders = 'take_orders';
  static const String viewOrders = 'view_orders';
  static const String cancelOrders = 'cancel_orders';

  /// All known keys, in display order.
  static const List<String> all = [takeOrders, viewOrders, cancelOrders];

  /// Human-readable label for a permission key.
  static String label(String key) => switch (key) {
        takeOrders => 'Take orders',
        viewOrders => 'View orders',
        cancelOrders => 'Cancel orders',
        _ => key,
      };

  /// Short description shown under the label in the admin UI.
  static String description(String key) => switch (key) {
        takeOrders => 'Add items to the cart and send orders to the kitchen',
        viewOrders => 'See recent orders and their status',
        cancelOrders => 'Cancel an order before it is served',
        _ => '',
      };

  /// Permissions granted to a brand-new waiter account by default.
  static const List<String> defaultPermissions = [takeOrders, viewOrders];

  /// Encodes a list of keys to a JSON array string for SQLite storage.
  static String encode(List<String> permissions) => jsonEncode(permissions);

  /// Decodes a JSON array string back to a list of keys.
  ///
  /// Falls back to an empty list for null/blank/invalid input so a malformed
  /// row never crashes the app.
  static List<String> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // Ignore malformed JSON and treat as no permissions.
    }
    return const [];
  }
}
