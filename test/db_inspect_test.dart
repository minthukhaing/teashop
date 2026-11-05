// Standalone database inspection test.
//
// It boots the REAL AppDatabase (schema + seed menu) using the FFI SQLite
// factory and a fake path_provider platform, so it runs on Windows desktop
// without an Android emulator or Visual Studio toolchain. It then prints
// every row in menu_items / orders / order_items.
//
// Run with:  flutter test test/db_inspect_test.dart
library teashop_pos.test.db_inspect_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:teashop_pos/data/database/app_database.dart';

/// Fake path_provider that points the database at a temp directory so the test
/// never touches the real user Documents folder and needs no method channel.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

void main() {
  late final Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Use the FFI SQLite engine so sqflite works on the host (Windows) without
    // a native plugin / Visual Studio toolchain.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Redirect path_provider to a fixed dir under the project (avoids the
    // platform method channel) so we can also dump the file with sqlite3.
    tempDir = Directory(r'c:\Users\admin\Desktop\teashopmobile\build\db_inspect');
    tempDir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  test('inspect database records', () async {
    final db = AppDatabase.instance;

    final menu = await db.getMenuItems();
    print('\n========== MENU ITEMS (${menu.length}) ==========');
    for (final m in menu) {
      print('  #${m.id} | ${m.name} | ${m.category} | '
          '\$${m.price.toStringAsFixed(2)} | available=${m.available}'
          '${m.description != null ? ' | ${m.description}' : ''}');
    }

    final orders = await db.getOrders();
    print('\n========== ORDERS (${orders.length}) ==========');
    for (final o in orders) {
      print('  #${o.id} | table=${o.tableNumber} | status=${o.status} | '
          'total=\$${o.total.toStringAsFixed(2)} | items=${o.items.length}'
          '${o.customerName != null ? ' | customer=${o.customerName}' : ''}');
      for (final it in o.items) {
        print('      - ${it.name} x${it.quantity} @ \$${it.price.toStringAsFixed(2)}');
      }
    }

    // Show the on-disk location for follow-up inspection with the sqlite3 CLI.
    print('\n========== DATABASE FILE ==========');
    print('  ${tempDir.path}\\teashop_pos.db');

    // The seed should always create the four default menu items.
    expect(menu.length, greaterThanOrEqualTo(4),
        reason: 'Seeded menu should have at least 4 default items');
  });
}
