library teashop_pos.core.constants;

/// Central constants for the Teashop POS application.
///
/// Keeps network ports, API paths, database settings and order statuses in one
/// place so the Admin Host, Waiter client and Kitchen Display stay consistent.
///
/// Note: This file is intentionally free of `dart:io` imports so it compiles on
/// web.  The [serverBindAddress] was moved to `app_server.dart` where `dart:io`
/// is already required.
class AppConstants {
  AppConstants._();

  /// Port the Admin Host HTTP server listens on.
  static const int serverPort = 8080;

  /// URL scheme used for local HTTP communication.
  static const String scheme = 'http';

  /// API version prefix for all REST endpoints.
  static const String apiPrefix = '/api';

  /// Health-check endpoint.
  static const String healthEndpoint = '/health';

  /// REST resource paths.
  static const String menuEndpoint = '/menu';
  static const String ordersEndpoint = '/orders';
  static const String tablesEndpoint = '/tables';

  /// Shop profile / billing settings (voucher header + Gov Tax %).
  static const String settingsEndpoint = '/settings';

  /// Authentication endpoint (login) for Waiter/Kitchen clients.
  static const String authEndpoint = '/auth';

  /// How often Waiter/KDS clients poll the Admin Host for new orders.
  static const Duration ordersPollInterval = Duration(seconds: 3);

  /// Local SQLite database file name.
  static const String databaseName = 'teashop_pos.db';

  /// Current SQLite schema version (bump + write a migration when it changes).
  static const int databaseVersion = 7;

  /// Bind to every IPv4 interface so Wi-Fi clients on the LAN can reach the host.
  static final InternetAddress serverBindAddress = InternetAddress.anyIPv4;

  /// Order statuses used across the app.
  static const String statusPending = 'pending';
  static const String statusPreparing = 'preparing';
  static const String statusReady = 'ready';
  static const String statusServed = 'served';
  static const String statusCancelled = 'cancelled';

  /// The bill has been settled at checkout (Cash / KPay / - ) - the order is
  /// closed and no longer editable, deletable or shown on the unpaid list.
  static const String statusPaid = 'paid';

  /// All statuses in kitchen workflow order.
  static List<String> get allOrderStatuses => [
        statusPending,
        statusPreparing,
        statusReady,
        statusServed,
        statusCancelled,
        statusPaid,
      ];

  /// Statuses that mean the bill is still UNPAID - the order is active and has
  /// not been paid/cleared yet.
  static List<String> get unpaidStatuses => [
        statusPending,
        statusPreparing,
        statusReady,
      ];

  /// Statuses that mean the bill has been cleared (paid out or voided).
  static List<String> get paidStatuses =>
      [statusServed, statusCancelled, statusPaid];

  /// Whether [status] still represents an unpaid / uncleared bill.
  ///
  /// Comparison is case-insensitive so mixed-case values coming from the
  /// database or a remote client are handled consistently.
  static bool isUnpaidStatus(String status) => unpaidStatuses
      .any((s) => s.toLowerCase() == status.trim().toLowerCase());

  /// Whether [status] represents a paid / cleared / voided bill.
  static bool isPaidOrCancelledStatus(String status) => paidStatuses
      .any((s) => s.toLowerCase() == status.trim().toLowerCase());

  /// Display label for a status.
  static String statusLabel(String status) => switch (status) {
        statusPending => 'Pending',
        statusPreparing => 'Preparing',
        statusReady => 'Ready',
        statusServed => 'Served',
        statusCancelled => 'Cancelled',
        statusPaid => 'Paid',
        _ => status,
      };

  /// Currency unit used across the app (Kyat, in Myanmar).
  static const String currency = 'ကျပ်';
}
