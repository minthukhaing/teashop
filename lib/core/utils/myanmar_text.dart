library teashop_pos.core.utils.myanmar_text;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Helpers that force Myanmar (and any other) text into Unicode **NFC** form.
///
/// Myanmar script can be encoded in either NFC (composed) or NFD (decomposed)
/// form. Mixing the two -  - e.g. an NFD string read from an external feed stored
/// next to NFC strings typed in-app -  - breaks Asat/Virama stacking and makes
/// `LIKE` searches miss matches. Normalising every value at the SQLite boundary
/// (see `MenuItem` / `Order` / `OrderItem` `toMap`/`fromMap`) keeps the database
/// and the UI in a single canonical form.
class MyanmarText {
  MyanmarText._();

  /// Returns [text] in NFC (canonical composed) form.
  static String normalize(String text) => unorm.nfc(text);

  /// Null-safe variant for optional columns (description, notes, - ).
  static String? normalizeNullable(String? text) =>
      text == null ? null : unorm.nfc(text);

  /// Recursively normalizes every string in a decoded JSON value to NFC.
  ///
  /// Applied at the HTTP boundary (Shelf requests and API responses) so
  /// Burmese text sent by one device is canonical before it reaches the UI or
  /// SQLite, regardless of the sender's Unicode composition form.
  static Object? normalizeJson(Object? value) {
    if (value is String) return normalize(value);
    if (value is List) {
      return value.map(normalizeJson).toList(growable: true);
    }
    if (value is Map) {
      return value.map<String, dynamic>((key, mapped) => MapEntry(
            key is String ? normalize(key) : key.toString(),
            normalizeJson(mapped),
          ));
    }
    return value;
  }
}
