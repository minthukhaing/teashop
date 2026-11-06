library teashop_pos.core.utils.myanmar_text;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Helpers that force Myanmar (and any other) text into Unicode **NFC** form.
///
/// Myanmar script can be encoded in either NFC (composed) or NFD (decomposed)
/// form. Mixing the two – e.g. an NFD string read from an external feed stored
/// next to NFC strings typed in-app – breaks Asat/Virama stacking and makes
/// `LIKE` searches miss matches. Normalising every value at the SQLite boundary
/// (see `MenuItem` / `Order` / `OrderItem` `toMap`/`fromMap`) keeps the database
/// and the UI in a single canonical form.
class MyanmarText {
  MyanmarText._();

  /// Returns [text] in NFC (canonical composed) form.
  static String normalize(String text) => unorm.nfc(text);

  /// Null-safe variant for optional columns (description, notes, …).
  static String? normalizeNullable(String? text) =>
      text == null ? null : unorm.nfc(text);
}
