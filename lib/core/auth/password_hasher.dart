library teashop_pos.core.auth.password_hasher;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Salts and SHA-256 hashes a plaintext password for storage in the `users`
/// table.
///
/// This is a single-tenant LAN point-of-sale, so we use a fixed application
/// salt plus SHA-256 (via the `crypto` package) rather than a slow KDF.
/// Passwords are never stored or logged in plaintext.
class PasswordHasher {
  PasswordHasher._();

  /// Application-wide salt. Adequate for a LAN POS; a multi-tenant system
  /// would use a random per-row salt stored alongside the hash.
  static const String _salt = 'teashop-pos::v1';

  /// Returns the hex-encoded SHA-256 digest of `salt + ':' + password`.
  static String hash(String password) {
    final bytes = utf8.encode('$_salt:$password');
    return sha256.convert(bytes).toString();
  }

  /// Returns `true` when [password] hashes to [storedHash].
  static bool verify(String password, String storedHash) {
    return hash(password) == storedHash;
  }
}
