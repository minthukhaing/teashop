library teashop_pos.presentation.app_mode;

import 'package:intl/intl.dart';

import '../client/waiter_api_service.dart';
import '../core/constants/app_constants.dart';
import '../data/models/order.dart';

/// The role the running instance of the app plays in the local Wi-Fi POS.
enum AppMode {
  /// Runs the shelf HTTP server + SQLite master database.
  admin,
  /// Places orders against the Admin Host.
  waiter,
  /// Displays incoming orders for the kitchen.
  kitchen,
}

/// Resolves the active mode from the `--dart-define=APP_MODE=...` build flag.
/// Falls back to [AppMode.admin] when no flag is provided.
AppMode currentAppMode() {
  final raw = const String.fromEnvironment('APP_MODE', defaultValue: '');
  switch (raw.toLowerCase()) {
    case 'admin':
      return AppMode.admin;
    case 'waiter':
      return AppMode.waiter;
    case 'kitchen':
      return AppMode.kitchen;
    default:
      return AppMode.admin;
  }
}

/// Shared client configuration used by Waiter and Kitchen instances.
///
/// The Admin Host IP is entered once (or auto-resolved) and reused for every
/// API call.
class AppConfig {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  String adminIp = '127.0.0.1';
  int serverPort = AppConstants.serverPort;

  WaiterApiService? _api;

  /// Date formatter for displaying order times.
  final DateFormat dateFormat = DateFormat.Hm();

  String get baseUrl => 'http://$adminIp:$serverPort';

  /// Lazily-built API client bound to the current [baseUrl].
  WaiterApiService get api => _api ??= WaiterApiService(baseUrl: baseUrl);

  /// Rebuilds the API client after [adminIp]/[serverPort] change.
  void resetApi() {
    _api?.dispose();
    _api = null;
  }

  /// Fetches the list of orders from the Admin Host.
  Future<List<Order>> getOrders({String? status, String? since}) async {
    return api.fetchOrders(status: status, since: since);
  }
}

