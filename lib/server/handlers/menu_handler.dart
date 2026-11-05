library teashop_pos.server.handlers.menu_handler;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../data/database/app_database.dart';
import '../../data/models/menu_item.dart';
import '../server_utils.dart';

/// Handles REST requests for menu items.
class MenuHandler {
  MenuHandler(this._database);
  final AppDatabase _database;

  /// GET /api/menu  (supports ?available=true|false)
  Future<Response> getMenu(Request request) async {
    final availableParam = request.url.queryParameters['available'];
    final items = await _database.getMenuItems(
      available: availableParam == null ? null : availableParam == 'true',
    );
    return jsonResponse(items.map((item) => item.toJson()).toList());
  }

  /// POST /api/menu
  Future<Response> createMenu(Request request) async {
    try {
      final body = await readJsonBody(request);
      final item = MenuItem(
        name: body['name'] as String? ?? '',
        description: body['description'] as String?,
        price: (body['price'] as num?)?.toDouble() ?? 0.0,
        category: body['category'] as String? ?? 'Other',
        available: body['available'] as bool? ?? true,
        imageUrl: body['imageUrl'] as String?,
        createdAt: DateTime.now(),
      );
      final id = await _database.insertMenuItem(item);
      return jsonResponse(item.copyWith(id: id).toJson(), statusCode: 201);
    } catch (e) {
      return errorResponse('Failed to create menu item: $e');
    }
  }

  /// PUT /api/menu/:id
  Future<Response> updateMenu(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      final body = await readJsonBody(request);
      final existing = (await _database.getMenuItems()).firstWhere(
        (element) => element.id == id,
        orElse: () => throw Exception('Menu item not found'),
      );
      final item = MenuItem(
        id: id,
        name: body['name'] as String? ?? existing.name,
        description: body['description'] as String? ?? existing.description,
        price: (body['price'] as num?)?.toDouble() ?? existing.price,
        category: body['category'] as String? ?? existing.category,
        available: body['available'] as bool? ?? existing.available,
        imageUrl: body['imageUrl'] as String? ?? existing.imageUrl,
        createdAt: existing.createdAt,
      );
      await _database.updateMenuItem(item);
      return jsonResponse(item.toJson());
    } catch (e) {
      return errorResponse('Failed to update menu item: $e');
    }
  }

  /// DELETE /api/menu/:id
  Future<Response> deleteMenu(Request request) async {
    try {
      final id = int.parse(request.params['id']!);
      await _database.deleteMenuItem(id);
      return jsonResponse({'success': true});
    } catch (e) {
      return errorResponse('Failed to delete menu item: $e');
    }
  }
}
