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

  /// GET /api/orders  (supports ?status=...&since=ISO8601&unpaid=true)
  Future<Response> getOrders(Request request) async {
    final status = request.url.queryParameters['status'];
    final since = request.url.queryParameters['since'];
    final unpaid = request.url.queryParameters['unpaid']?.toLowerCase() == 'true';
    final orders = await _database.getOrders(
      status: status == null || status.isEmpty ? null : status,
      since: since == null || since.isEmpty ? null : since,
      unpaidOnly: unpaid,
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
        waiterName: body['waiterName'] as String?,
        createdAt: DateTime.now(),
        items: items,
      );

      final saved = await _database.insertOrAppendOrder(order);
      return jsonResponse(saved.toJson(), statusCode: 201);
    } catch (e) {
      return errorResponse('Failed to create order: $e');
    }
  }

  /// PATCH /api/orders/:id
  ///
  /// Body: `{ "status": "..." }` - or, for checkout,
  /// `{ "status": "paid", "paymentMethod": "cash" | "kpay" | ... }` which
  /// records how and when the bill was settled.
  Future<Response> updateOrderStatus(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final body = await readJsonBody(request);
      final status = body['status'] as String?;
      if (status == null || status.isEmpty) {
        return errorResponse('status is required');
      }
      if (status == AppConstants.statusPaid) {
        final paymentMethod =
            (body['paymentMethod'] as String?)?.trim().isNotEmpty == true
                ? body['paymentMethod'] as String
                : 'cash';
        final changed = await _database.markOrderPaid(id, paymentMethod);
        if (changed == 0) {
          return errorResponse('Order $id not found', statusCode: 404);
        }
        return jsonResponse(
            {'success': true, 'id': id, 'status': status, 'paymentMethod': paymentMethod});
      }
      await _database.updateOrderStatus(id, status);
      return jsonResponse({'success': true, 'id': id, 'status': status});
    } catch (e) {
      return errorResponse('Failed to update order status: $e');
    }
  }

  /// PUT /api/orders/:id - full edit of an unpaid order (items, quantities,
  /// table, notes).  The total is recomputed from the submitted line items.
  /// Editing is only allowed while the bill is still unpaid.
  Future<Response> updateOrder(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final existing = await _database.getOrder(id);
      if (existing == null) {
        return errorResponse('Order $id not found', statusCode: 404);
      }
      if (!AppConstants.isUnpaidStatus(existing.status)) {
        return errorResponse(
            'Order $id is already paid/cleared and can no longer be edited.',
            statusCode: 409);
      }

      final body = await readJsonBody(request);
      final items = (body['items'] as List<dynamic>?)
              ?.map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];
      if (items.isEmpty) {
        return errorResponse(
            'An order must keep at least one item. Use DELETE to remove it.');
      }

      final tableNumber = body['tableNumber'] as String?;
      final updated = existing.copyWith(
        tableNumber: tableNumber != null && tableNumber.isNotEmpty
            ? tableNumber
            : existing.tableNumber,
        notes: body['notes'] as String?,
        customerName: body['customerName'] as String?,
        waiterName: body['waiterName'] as String?,
        items: items,
      );

      final changed = await _database.updateOrder(updated);
      if (changed == 0) {
        return errorResponse('Order $id not found', statusCode: 404);
      }

      // Re-read so the response carries the recomputed total + fresh items.
      final saved = await _database.getOrder(id);
      return jsonResponse(saved!.toJson());
    } catch (e) {
      return errorResponse('Failed to update order: $e');
    }
  }

  /// DELETE /api/orders/:id - permanently removes an unpaid order (and its
  /// line items via the cascade FK) before it is closed/paid.
  Future<Response> deleteOrder(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final existing = await _database.getOrder(id);
      if (existing == null) {
        return errorResponse('Order $id not found', statusCode: 404);
      }
      if (!AppConstants.isUnpaidStatus(existing.status)) {
        return errorResponse(
            'Order $id is already paid/cleared and can no longer be deleted.',
            statusCode: 409);
      }
      await _database.deleteOrder(id);
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      return errorResponse('Failed to delete order: $e');
    }
  }
}
