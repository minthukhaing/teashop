library teashop_pos.core.constants;

import 'dart:io';

/// Central constants for the Teashop POS application.
///
/// Keeps network ports, API paths, database settings and order statuses in one
/// place so the Admin Host, Waiter client and Kitchen Display stay consistent.
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

  /// Authentication endpoint (login) for Waiter/Kitchen clients.
  static const String authEndpoint = '/auth';

  /// How often Waiter/KDS clients poll the Admin Host for new orders.
  static const Duration ordersPollInterval = Duration(seconds: 3);

  /// Local SQLite database file name.
  static const String databaseName = 'teashop_pos.db';

  /// Current SQLite schema version (bump + write a migration when it changes).
  static const int databaseVersion = 4;

  /// Bind to every IPv4 interface so Wi-Fi clients on the LAN can reach the host.
  static final InternetAddress serverBindAddress = InternetAddress.anyIPv4;

  /// Order statuses used across the app.
  static const String statusPending = 'pending';
  static const String statusPreparing = 'preparing';
  static const String statusReady = 'ready';
  static const String statusServed = 'served';
  static const String statusCancelled = 'cancelled';

  /// All statuses in kitchen workflow order.
  static List<String> get allOrderStatuses => [
        statusPending,
        statusPreparing,
        statusReady,
        statusServed,
        statusCancelled,
      ];

  /// Display label for a status.
  static String statusLabel(String status) => switch (status) {
        statusPending => 'Pending',
        statusPreparing => 'Preparing',
        statusReady => 'Ready',
        statusServed => 'Served',
        statusCancelled => 'Cancelled',
        _ => status,
      };

  /// Default currency symbol.
  static const String currency = '\$';
}
