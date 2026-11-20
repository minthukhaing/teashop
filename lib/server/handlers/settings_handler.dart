library teashop_pos.server.handlers.settings_handler;

import 'package:shelf/shelf.dart';

import '../../data/database/app_database.dart';
import '../server_utils.dart';

/// Handles REST requests for shop profile / billing settings.
class SettingsHandler {
  SettingsHandler(this._database);
  final AppDatabase _database;

  /// GET /api/settings - shop name, address and Gov Tax % used on vouchers.
  Future<Response> getSettings(Request request) async {
    final settings = await _database.getShopSettings();
    return jsonResponse(settings.toJson());
  }

  /// PUT /api/settings - updates the single settings row.
  Future<Response> updateSettings(Request request) async {
    try {
      final body = await readJsonBody(request);
      final current = await _database.getShopSettings();
      final updated = current.copyWith(
        shopName: body['shopName'] as String?,
        shopAddress: body['shopAddress'] as String?,
        govTaxPercent: (body['govTaxPercent'] as num?)?.toDouble(),
      );
      await _database.saveShopSettings(updated);
      return jsonResponse(updated.toJson());
    } catch (e) {
      return errorResponse('Failed to update settings: $e');
    }
  }
}
