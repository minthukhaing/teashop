library teashop_pos.server.handlers.tables_handler;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/utils/myanmar_text.dart';
import '../../data/database/app_database.dart';
import '../../data/models/table.dart';
import '../server_utils.dart';

/// Handles REST requests for dining tables.
///
/// The Admin Host owns the canonical `tables` list in SQLite.  Waiter and
/// Kitchen clients sync from it via `GET /api/tables`, while the Admin
/// manages add/remove through `POST` / `DELETE`.
class TablesHandler {
  TablesHandler(this._database);
  final AppDatabase _database;

  /// GET /api/tables  (supports ?active=true|false)
  Future<Response> getTables(Request request) async {
    final activeParam = request.url.queryParameters['active'];
    final tables = await _database.getTables(
      activeOnly: activeParam == null ? null : activeParam == 'true',
    );
    return jsonResponse(tables.map((t) => t.toJson()).toList());
  }

  /// POST /api/tables
  ///
  /// Body: `{ "number": "T1", "capacity": 4, "isActive": true }`
  ///
  /// Rejects empty or duplicate table numbers.
  Future<Response> createTable(Request request) async {
    try {
      final body = await readJsonBody(request);
      final number = MyanmarText.normalize(
          (body['number'] as String? ?? '').trim());
      if (number.isEmpty) {
        return errorResponse('Table number is required', statusCode: 400);
      }
      final existing = await _database.getTableByNumber(number);
      if (existing != null) {
        return errorResponse('Table "$number" already exists', statusCode: 409);
      }
      final capacity = (body['capacity'] as num?)?.toInt() ?? 4;
      if (capacity <= 0) {
        return errorResponse('Capacity must be greater than 0', statusCode: 400);
      }
      final table = TableModel(
        number: number,
        capacity: capacity,
        isActive: body['isActive'] as bool? ?? true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final id = await _database.insertTable(table);
      return jsonResponse(table.copyWith(id: id).toJson(), statusCode: 201);
    } catch (e) {
      return errorResponse('Failed to create table: $e');
    }
  }

  /// DELETE /api/tables/:id
  ///
  /// Refuses to delete a table that still has unpaid (pending/preparing/ready)
  /// orders, so active bills are never orphaned.  Return 409 in that case.
  Future<Response> deleteTable(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final table = await _database.getTable(id);
      if (table == null) {
        return errorResponse('Table $id not found', statusCode: 404);
      }
      final activeOrders =
          await _database.countActiveOrdersForTable(table.number);
      if (activeOrders > 0) {
        return errorResponse(
          'Cannot delete "${table.number}": it has $activeOrders '
              'unpaid order(s). Close or move those orders first.',
          statusCode: 409,
        );
      }
      await _database.deleteTable(id);
      return jsonResponse({'success': true, 'id': id});
    } catch (e) {
      return errorResponse('Failed to delete table: $e');
    }
  }
}
