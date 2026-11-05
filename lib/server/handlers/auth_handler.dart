library teashop_pos.server.handlers.auth_handler;

import 'package:shelf/shelf.dart';

import '../../data/database/app_database.dart';
import '../server_utils.dart';

/// Handles authentication requests from Waiter (and Kitchen) clients.
///
/// Credentials are validated against the `users` table on the Admin Host; on
/// success the granted permissions are returned so the client can enforce them
/// locally.
class AuthHandler {
  AuthHandler(this._database);
  final AppDatabase _database;

  /// POST /api/auth/login  body: { "username": "...", "password": "..." }
  ///
  /// Returns 200 with the user + permissions on success, 401 on bad creds.
  Future<Response> login(Request request) async {
    try {
      final body = await readJsonBody(request);
      final username = (body['username'] as String?)?.trim() ?? '';
      final password = body['password'] as String? ?? '';
      if (username.isEmpty || password.isEmpty) {
        return errorResponse('Username and password are required',
            statusCode: 400);
      }
      final user = await _database.authenticateUser(username, password);
      if (user == null) {
        return errorResponse('Invalid username or password', statusCode: 401);
      }
      return jsonResponse({
        'success': true,
        'user': {
          'id': user.id,
          'username': user.username,
          'displayName': user.displayName,
          'role': user.role,
          'permissions': user.permissions,
        },
      });
    } catch (e) {
      return errorResponse('Failed to authenticate: $e', statusCode: 500);
    }
  }
}
