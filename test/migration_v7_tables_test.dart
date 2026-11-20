// Migration test for the v6 -> v7 schema upgrade (`tables` table).
//
// Simulates a REAL upgrade: a database file is created at the previous v6
// schema with an order + line item, then opened through [AppDatabase] so the
// v6 -> v7 migration runs.  Verifies that the `tables` table is created and
// pre-seeded with T1..T12, and that Admin-level table CRUD works on top of it.
library teashop_pos.test.migration_v7_tables_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/core/utils/myanmar_text.dart';
import 'package:teashop_pos/data/database/app_database.dart';
import 'package:teashop_pos/data/models/order.dart';
import 'package:teashop_pos/data/models/table.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final tempDir =
      Directory.systemTemp.createTempSync('teashop_migration_v7_tables');
  final dbPath = p.join(tempDir.path, AppConstants.databaseName);

  test('v6 -> v7 migration creates the tables table and seeds T1..T12',
      () async {
    // Phase A: create a legacy v6 database with an order + line item.
    final legacy = await databaseFactory.openDatabase(
      dbPath,
      options: sqflite.OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE menu_items (
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              name        TEXT NOT NULL,
              description TEXT,
              price       REAL NOT NULL CHECK (price >= 0),
              category    TEXT NOT NULL,
              available   INTEGER NOT NULL DEFAULT 1
                            CHECK (available IN (0, 1)),
              image_url   TEXT,
              created_at  TEXT NOT NULL,
              updated_at  TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE orders (
              id             INTEGER PRIMARY KEY AUTOINCREMENT,
              table_number   TEXT    NOT NULL,
              status         TEXT    NOT NULL
                                CHECK (status IN ('pending', 'preparing',
                                                       'ready', 'served',
                                                       'cancelled', 'paid')),
              total          REAL    NOT NULL DEFAULT 0 CHECK (total >= 0),
              customer_name  TEXT,
              notes          TEXT,
              waiter_name    TEXT,
              payment_method TEXT,
              paid_at        TEXT,
              created_at     TEXT    NOT NULL,
              updated_at     TEXT    NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE order_items (
              id            INTEGER PRIMARY KEY AUTOINCREMENT,
              order_id      INTEGER NOT NULL,
              menu_item_id  INTEGER,
              name          TEXT    NOT NULL,
              price         REAL    NOT NULL CHECK (price >= 0),
              quantity      INTEGER NOT NULL DEFAULT 1
                                CHECK (quantity >= 1),
              notes         TEXT,
              customizations TEXT,
              created_at    TEXT    NOT NULL,
              updated_at    TEXT    NOT NULL,
              FOREIGN KEY (order_id) REFERENCES orders (id)
                ON DELETE CASCADE,
              FOREIGN KEY (menu_item_id) REFERENCES menu_items (id)
                ON DELETE SET NULL
            )
          ''');
          await db.insert(
            'orders',
            {
              'table_number': 'T-1',
              'status': 'pending',
              'total': 5.0,
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        },
      ));
    await legacy.close();

    // Phase B: open through AppDatabase - v6 -> v7 migration runs.
    AppDatabase.overridePathForTesting = dbPath;
    final appDb = AppDatabase.instance;
    try {
      // The new tables table must exist and be pre-seeded with T1..T12.
      final tables = await appDb.getTables();
      expect(tables, isNotNull);
      expect(tables.length, 12);
      for (var i = 1; i <= 12; i++) {
        final found = tables.any((t) => t.number == 'T$i');
        expect(found, isTrue, reason: 'T$i should be seeded by migration');
      }

      expect(
        await appDb.getTableByNumber('T1'),
        isA<TableModel>(),
      );

      // Admin CRUD on top of the newly-migrated database.
      final id = await appDb.insertTable(
        TableModel(
          number: 'T13',
          capacity: 2,
          isActive: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      expect(id, greaterThan(0));
      final added = await appDb.getTable(id);
      expect(added, isNotNull);
      expect(added!.number, 'T13');
      expect(added.capacity, 2);

      // The API uses this count to refuse deleting a table with unpaid orders.
      final activeOrders = await appDb.countActiveOrdersForTable('T-1');
      expect(activeOrders, greaterThan(0));

      await appDb.deleteTable(id);
      final deleted = await appDb.getTable(id);
      expect(deleted, isNull);
    } finally {
      await appDb.close();
      AppDatabase.overridePathForTesting = null;
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  });

  test('fresh v7 database seeds defaults and keeps admin deletions', () async {
    final freshDir =
        Directory.systemTemp.createTempSync('teashop_fresh_v7_tables');
    final freshPath = p.join(freshDir.path, AppConstants.databaseName);
    addTearDown(() async {
      await AppDatabase.instance.close();
      AppDatabase.overridePathForTesting = null;
      if (freshDir.existsSync()) freshDir.deleteSync(recursive: true);
    });
    AppDatabase.overridePathForTesting = freshPath;

    final firstOpen = AppDatabase.instance;
    final defaults = await firstOpen.getTables();
    expect(defaults.length, 12);
    for (final table in defaults) {
      await firstOpen.deleteTable(table.id!);
    }
    await firstOpen.close();

    final reopened = AppDatabase.instance;
    expect(await reopened.getTables(), isEmpty);
  });

  test('table lookup and unpaid counts use NFC-normalized numbers', () async {
    final dir = Directory.systemTemp.createTempSync('teashop_table_nfc');
    addTearDown(() async {
      await AppDatabase.instance.close();
      AppDatabase.overridePathForTesting = null;
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    AppDatabase.overridePathForTesting =
        p.join(dir.path, AppConstants.databaseName);
    final database = AppDatabase.instance;

    const composed = 'T\u00e9';
    final decomposed = 'T\u0065\u0301';
    final id = await database.insertTable(TableModel(
      number: composed,
      capacity: 2,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    expect((await database.getTableByNumber(decomposed))?.id, id);

    await database.insertOrder(Order(
      tableNumber: composed,
      total: 1.0,
      createdAt: DateTime.now(),
    ));
    expect(await database.countActiveOrdersForTable(decomposed), 1);
    expect(MyanmarText.normalize(decomposed), composed);
  });
}
