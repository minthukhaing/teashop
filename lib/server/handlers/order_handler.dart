library teashop_pos.server.handlers.order_handler;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/models/order.dart';
import '../../data/models/order_item.dart';
import '../server_utils.dart';

/// Handles REST requests for orders.
class OrderHandler {
  OrderHandler(this._database);
  final AppDatabase _database;

  /// GET /api/orders  (supports ?status=...&since=ISO8601)
  Future<Response> getOrders(Request request) async {
    final status = request.url.queryParameters['status'];
    final since = request.url.queryParameters['since'];
    final orders = await _database.getOrders(
      status: status == null || status.isEmpty ? null : status,
      since: since == null || since.isEmpty ? null : since,
    );
    return jsonResponse(orders.map((order) => order.toJson()).toList());
  }

  /// POST /api/orders
  Future<Response> createOrder(Request request) async {
    try {
      final body = await readJsonBody(request);
      final items = (body['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      final total = items.fold<double>(0, (sum, item) => sum + item.subtotal);

      final order = Order(
        tableNumber: body['tableNumber'] as String? ?? '',
        status: AppConstants.statusPending,
        total: total,
        customerName: body['customerName'] as String?,
        notes: body['notes'] as String?,
        createdAt: DateTime.now(),
        items: items,
      );

      final id = await _database.insertOrder(order);
      return jsonResponse(order.copyWith(id: id).toJson(), statusCode: 201);
    } catch (e) {
      return errorResponse('Failed to create order: $e');
    }
  }

  /// PATCH /api/orders/:id  (body: { "status": "..." })
  Future<Response> updateOrderStatus(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final body = await readJsonBody(request);
      final status = body['status'] as String?;
      if (status == null || status.isEmpty) {
        return errorResponse('status is required');
      }
      await _database.updateOrderStatus(id, status);
      return jsonResponse({'success': true, 'id': id, 'status': status});
    } catch (e) {
      return errorResponse('Failed to update order status: $e');
    }
  }
}
