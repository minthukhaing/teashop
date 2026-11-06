// Unit tests for Myanmar Unicode NFC normalisation at the SQLite boundary.
//
// Run with:  flutter test test/myanmar_text_test.dart
library teashop_pos.test.myanmar_text_test;

import 'package:flutter_test/flutter_test.dart';

import 'package:teashop_pos/core/utils/myanmar_text.dart';
import 'package:teashop_pos/data/models/menu_item.dart';

void main() {
  group('MyanmarText.normalize (NFC)', () {
    test('composes a decomposed (NFD) sequence into NFC', () {
      // "A" + combining grave accent (U+0300) is the NFD form of "À" (U+00C0).
      const nfd = 'A\u0300';
      const nfc = '\u00C0';
      expect(MyanmarText.normalize(nfd), nfc);
    });

    test('is idempotent on Myanmar text', () {
      const myanmar = 'လက်ဖက်ရည်'; // "tea"
      final once = MyanmarText.normalize(myanmar);
      expect(MyanmarText.normalize(once), once);
    });

    test('leaves already-NFC Myanmar text unchanged', () {
      const myanmar = 'ကော်ဖီ'; // "coffee"
      expect(MyanmarText.normalize(myanmar), myanmar);
    });

    test('nullable variant preserves null and empties', () {
      expect(MyanmarText.normalizeNullable(null), isNull);
      expect(MyanmarText.normalizeNullable(''), '');
    });

    test('MenuItem toMap/fromMap round-trips as NFC', () {
      // The DB boundary must always store and return NFC text.
      final item = MenuItem(
        name: 'လက်ဖက်ရည်',
        price: 1.50,
        category: 'Beverages',
        description: 'အိမ်လုပ် လက်ဖက်ရည်',
      );
      final restored = MenuItem.fromMap(item.toMap());
      expect(restored.name, MyanmarText.normalize('လက်ဖက်ရည်'));
      expect(restored.category, 'Beverages');
      expect(restored.description, MyanmarText.normalize('အိမ်လုပ် လက်ဖက်ရည်'));
    });
  });
}
