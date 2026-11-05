library teashop_pos.core.auth.waiter_auth;

/// In-memory session for the logged-in waiter (client side).
///
/// Populated after a successful `/api/auth/login` against the Admin Host and
/// consulted by the waiter UI to gate actions by permission. The session lives
/// only for the current app run, which is fine for a LAN POS terminal.
class WaiterAuth {
  WaiterAuth._();
  static final WaiterAuth instance = WaiterAuth._();

  bool _loggedIn = false;
  String _username = '';
  String? _displayName;
  List<String> _permissions = const [];

  bool get isLoggedIn => _loggedIn;
  String get username => _username;
  String? get displayName => _displayName;

  /// Display name to show in the AppBar, falling back to the username.
  String get displayNameOrUsername =>
      (_displayName != null && _displayName!.isNotEmpty) ? _displayName! : _username;

  /// An unmodifiable copy of the granted permission keys.
  List<String> get permissions => List.unmodifiable(_permissions);

  /// Returns `true` when the session is active and [key] is granted.
  bool can(String key) => _loggedIn && _permissions.contains(key);

  /// Starts a new session, replacing any previous one.
  void startSession({
    required String username,
    String? displayName,
    required List<String> permissions,
  }) {
    _loggedIn = true;
    _username = username;
    _displayName = displayName;
    _permissions = List<String>.from(permissions);
  }

  /// Clears the current session.
  void logout() {
    _loggedIn = false;
    _username = '';
    _displayName = null;
    _permissions = const [];
  }
}
