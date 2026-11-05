library teashop_pos.data.models.user_account;

import '../../core/auth/waiter_permissions.dart';

/// A user account row from the `users` table.
///
/// The password hash is intentionally excluded from this model — it is used for
/// listing accounts and for the authenticated session. Hashing is handled
/// inside [AppDatabase] so the plaintext never leaves the database layer.
class UserAccount {
  const UserAccount({
    this.id,
    required this.username,
    required this.role,
    this.displayName,
    this.permissions = const [],
    this.active = true,
    this.createdAt,
  });

  final int? id;
  final String username;
  final String role; // 'admin' | 'waiter'
  final String? displayName;
  final List<String> permissions;
  final bool active;
  final DateTime? createdAt;

  bool get isWaiter => role == 'waiter';
  bool get isAdmin => role == 'admin';

  factory UserAccount.fromMap(Map<String, Object?> map) {
    return UserAccount(
      id: map['id'] as int?,
      username: map['username'] as String,
      role: map['role'] as String,
      displayName: map['display_name'] as String?,
      permissions: WaiterPermissions.decode(map['permissions'] as String?),
      active: (map['active'] as int?)?.toInt() == 1,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'username': username,
      'role': role,
      'display_name': displayName,
      'permissions': WaiterPermissions.encode(permissions),
      'active': active ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  UserAccount copyWith({
    int? id,
    String? username,
    String? role,
    String? displayName,
    List<String>? permissions,
    bool? active,
    DateTime? createdAt,
  }) {
    return UserAccount(
      id: id ?? this.id,
      username: username ?? this.username,
      role: role ?? this.role,
      displayName: displayName ?? this.displayName,
      permissions: permissions ?? this.permissions,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'UserAccount(id: $id, username: $username, role: $role, active: $active)';
}
