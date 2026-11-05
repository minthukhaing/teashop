library teashop_pos.core.auth;

import '../../data/database/app_database.dart';

/// Session-based authentication for the Admin Host.
///
/// Credentials are validated against the `users` table (role = 'admin') in the
/// local SQLite database, so password changes persist across restarts.  The
/// session itself lives in memory for the current app run.
class AdminAuth {
  AdminAuth._();
  static final AdminAuth instance = AdminAuth._();

  /// Default credentials seeded into the database on first run.
  static const String defaultUsername = 'admin';
  static const String defaultPassword = 'admin123';

  bool _loggedIn = false;
  int? _userId;
  String _username = '';

  bool get isLoggedIn => _loggedIn;
  String get username => _username;

  /// Validates [username] / [password] against the database and starts a
  /// session when they match an active admin account.
  Future<bool> login(String username, String password) async {
    final user =
        await AppDatabase.instance.authenticateUser(username, password);
    if (user == null || !user.isAdmin) return false;
    _loggedIn = true;
    _userId = user.id;
    _username = user.username;
    return true;
  }

  /// Clears the current session.
  void logout() {
    _loggedIn = false;
    _userId = null;
    _username = '';
  }

  /// Updates the password after verifying the old one.
  ///
  /// Returns `false` if the old password is wrong, the new one is shorter than
  /// 4 characters, or there is no active session.
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (_userId == null || newPassword.length < 4) return false;
    final user =
        await AppDatabase.instance.authenticateUser(_username, oldPassword);
    if (user == null || user.id != _userId) return false;
    await AppDatabase.instance.updateUserPassword(_userId!, newPassword);
    return true;
  }
}
