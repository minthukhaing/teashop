library teashop_pos.client.waiter_api_service;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/utils/myanmar_text.dart';
import '../data/models/menu_item.dart';
import '../data/models/order.dart';
import '../data/models/shop_settings.dart';
import '../data/models/table.dart';

/// Decodes a UTF-8 JSON object response and normalizes Burmese text to NFC.
Map<String, dynamic> _decodeJsonObject(List<int> bytes) =>
    MyanmarText.normalizeJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>)
        as Map<String, dynamic>;

/// Decodes a UTF-8 JSON list response and normalizes Burmese text to NFC.
List<dynamic> _decodeJsonList(List<int> bytes) =>
    MyanmarText.normalizeJson(jsonDecode(utf8.decode(bytes)) as List<dynamic>)
        as List<dynamic>;

/// HTTP client used by Waiter and Kitchen clients to talk to the Admin Host.
///
/// All requests go over the local Wi-Fi network to the Admin Host's IP address.
class WaiterApiService {
  WaiterApiService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  /// Base URL of the Admin Host, e.g. `http://192.168.1.45:8080`.
  final String baseUrl;

  final http.Client _client;

  /// Builds a full URL for an API path.
  Uri _url(String path) => Uri.parse('$baseUrl${AppConstants.apiPrefix}$path');

  /// Pings the Admin Host health endpoint.
  ///
  /// Returns `true` when the server is reachable and responding, `false` on any
  /// network error.  Used by Waiter/Kitchen screens to give the operator an
  /// immediate "server unreachable" message before attempting a full API call.
  Future<bool> checkHealth() async {
    try {
      final response = await _client.get(
        Uri.parse('$baseUrl${AppConstants.healthEndpoint}'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<MenuItem>> fetchMenu() async {
    final response = await _client.get(_url(AppConstants.menuEndpoint));
    if (response.statusCode != 200) {
      throw Exception('Failed to load menu: ${response.statusCode}');
    }
    final List<dynamic> decoded = _decodeJsonList(response.bodyBytes);
    return decoded.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fetches the canonical list of tables from the Admin Host.  Waiters use
  /// this to render the tables grid so it always matches the Admin's
  /// configured floor plan (active tables only by default).
  Future<List<TableModel>> fetchTables({bool activeOnly = true}) async {
    final query = <String, String>{};
    if (activeOnly) query['active'] = 'true';
    final url = _url(AppConstants.tablesEndpoint)
        .replace(queryParameters: query);
    final response = await _client.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to load tables: ${response.statusCode}');
    }
    final List<dynamic> decoded = _decodeJsonList(response.bodyBytes);
    return decoded.map((e) => TableModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Creates a new table on the Admin Host.
  Future<TableModel> createTable(TableModel table) async {
    final response = await _client.post(
      _url(AppConstants.tablesEndpoint),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(table.toJson()),
    );
    if (response.statusCode != 201) {
      final body = _decodeJsonObject(response.bodyBytes);
      throw Exception(body['error'] ?? 'Failed to create table (HTTP ${response.statusCode})');
    }
    return TableModel.fromJson(
        _decodeJsonObject(response.bodyBytes));
  }

  /// Deletes a table on the Admin Host.  Throws a 409-flavored error when the
  /// table still has unpaid orders.
  Future<void> deleteTable(int id) async {
    final response = await _client.delete(
      _url('${AppConstants.tablesEndpoint}/$id'),
    );
    if (response.statusCode != 200) {
      final body = _decodeJsonObject(response.bodyBytes);
      throw Exception(body['error'] ?? 'Failed to delete table (HTTP ${response.statusCode})');
    }
  }
  Future<Order> submitOrder(Order order) async {
    final response = await _client.post(
      _url(AppConstants.ordersEndpoint),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(order.toJson()),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to submit order: ${response.statusCode}');
    }
    return Order.fromJson(_decodeJsonObject(response.bodyBytes));
  }

  /// Fetches orders, optionally filtered by status, a `since` timestamp, or
  /// unpaid-only (active orders whose bill has not been paid/cleared yet).
  Future<List<Order>> fetchOrders(
      {String? status, String? since, bool unpaidOnly = false}) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (since != null && since.isNotEmpty) query['since'] = since;
    if (unpaidOnly) query['unpaid'] = 'true';

    final url = _url(AppConstants.ordersEndpoint).replace(queryParameters: query);
    final response = await _client.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to load orders: ${response.statusCode}');
    }
    final List<dynamic> decoded = _decodeJsonList(response.bodyBytes);
    return decoded.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Fully updates an unpaid order (items, quantities, notes) on the Admin
  /// Host.  The server recomputes the total from the submitted line items.
  /// Returns the updated order as stored by the server.
  Future<Order> updateOrder(Order order) async {
    final response = await _client.put(
      _url('${AppConstants.ordersEndpoint}/${order.id}'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(order.toJson()),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update order: ${response.statusCode}');
    }
    return Order.fromJson(_decodeJsonObject(response.bodyBytes));
  }

  /// Permanently deletes an unpaid order before it is closed/paid.
  Future<void> deleteOrder(int orderId) async {
    final response = await _client.delete(
      _url('${AppConstants.ordersEndpoint}/$orderId'),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete order: ${response.statusCode}');
    }
  }

  /// Updates an order's status (used by Kitchen/Admin).
  Future<void> updateOrderStatus(int orderId, String status) async {
    final response = await _client.patch(
      _url('${AppConstants.ordersEndpoint}/$orderId'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'status': status}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update order status: ${response.statusCode}');
    }
  }

  /// Checks out (settles) an unpaid order: marks it PAID on the Admin Host and
  /// records how the bill was paid (e.g. `cash`, `kpay`).
  Future<void> checkoutOrder(int orderId, String paymentMethod) async {
    final response = await _client.patch(
      _url('${AppConstants.ordersEndpoint}/$orderId'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'status': AppConstants.statusPaid,
        'paymentMethod': paymentMethod,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to checkout order: ${response.statusCode}');
    }
  }

  /// Fetches the shop profile / billing settings from the Admin Host
  /// (shop name, address and Gov Tax % - used on the POS voucher).
  Future<ShopSettings> fetchShopSettings() async {
    final response = await _client.get(_url(AppConstants.settingsEndpoint));
    if (response.statusCode != 200) {
      throw Exception('Failed to load settings: ${response.statusCode}');
    }
    return ShopSettings.fromJson(
        _decodeJsonObject(response.bodyBytes));
  }

  /// Authenticates a waiter against the Admin Host.
  ///
  /// Returns a [WaiterLoginResult]; check [WaiterLoginResult.success]. Throws
  /// on network errors so the caller can distinguish "unreachable" from
  /// "bad credentials".
  Future<WaiterLoginResult> login(String username, String password) async {
    final response = await _client.post(
      _url('${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      final body = _decodeJsonObject(response.bodyBytes);
      final user = body['user'] as Map<String, dynamic>;
      return WaiterLoginResult(
        success: true,
        username: user['username'] as String? ?? username,
        displayName: user['displayName'] as String?,
        permissions: (user['permissions'] as List<dynamic>?)
                ?.whereType<String>()
                .toList() ??
            const [],
      );
    }
    if (response.statusCode == 401) {
      return const WaiterLoginResult(
          success: false, errorMessage: 'Invalid username or password.');
    }
    return WaiterLoginResult(
      success: false,
      errorMessage: 'Login failed (HTTP ${response.statusCode}).',
    );
  }

  void dispose() => _client.close();
}

/// Outcome of a waiter login attempt against the Admin Host.
class WaiterLoginResult {
  const WaiterLoginResult({
    required this.success,
    this.errorMessage,
    this.username = '',
    this.displayName,
    this.permissions = const [],
  });

  final bool success;
  final String? errorMessage;
  final String username;
  final String? displayName;
  final List<String> permissions;
}
