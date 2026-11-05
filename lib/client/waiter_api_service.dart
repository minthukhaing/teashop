library teashop_pos.client.waiter_api_service;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../data/models/menu_item.dart';
import '../data/models/order.dart';

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
    final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Submits a new order to the Admin Host.
  Future<Order> submitOrder(Order order) async {
    final response = await _client.post(
      _url(AppConstants.ordersEndpoint),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode(order.toJson()),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to submit order: ${response.statusCode}');
    }
    return Order.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Fetches orders, optionally filtered by status or a `since` timestamp.
  Future<List<Order>> fetchOrders({String? status, String? since}) async {
    final query = <String, String>{};
    if (status != null && status.isNotEmpty) query['status'] = status;
    if (since != null && since.isNotEmpty) query['since'] = since;

    final url = _url(AppConstants.ordersEndpoint).replace(queryParameters: query);
    final response = await _client.get(url);
    if (response.statusCode != 200) {
      throw Exception('Failed to load orders: ${response.statusCode}');
    }
    final List<dynamic> decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
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
      final body = jsonDecode(response.body) as Map<String, dynamic>;
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
