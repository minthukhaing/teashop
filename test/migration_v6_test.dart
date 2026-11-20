// Migration test for the v5 → v6 schema upgrade (`paid` status + payment
// tracking).
//
// Simulates a REAL upgrade: a database file is created at the previous v5
// schema (old status CHECK, no payment columns) with orders AND line items,
// then opened through [AppDatabase] so the migration runs.  Verifies that:
//  * all orders and their line items survive the table rebuild (the old
//    naive DROP TABLE would have cascade-deleted every order_item),
//  * the `paid` status is now accepted by the widened CHECK, and
//  * `markOrderPaid` records the payment method and timestamp.
library teashop_pos.test.migration_v6_test;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/data/database/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final tempDir = Directory.systemTemp.createTempSync('teashop_migration');
  final dbPath = p.join(tempDir.path, AppConstants.databaseName);

  test('v5 → v6 migration preserves orders, items and allows paid status',
      () async {
    // ---- Phase A: create a legacy v5 database with data. ----
    final legacy = await databaseFactory.openDatabase(
      dbPath,
      options: sqflite.OpenDatabaseOptions(
        version: 5,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menu_items (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            name        TEXT    NOT NULL,
            description TEXT,
            price       REAL    NOT NULL CHECK (price >= 0),
            category    TEXT    NOT NULL,
            available   INTEGER NOT NULL DEFAULT 1 CHECK (available IN (0, 1)),
            image_url   TEXT,
            created_at  TEXT    NOT NULL,
            updated_at  TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE orders (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            table_number  TEXT    NOT NULL,
            status        TEXT    NOT NULL
                                  CHECK (status IN ('pending','preparing','ready','served','cancelled')),
            total         REAL    NOT NULL DEFAULT 0 CHECK (total >= 0),
            customer_name TEXT,
            notes         TEXT,
            waiter_name    TEXT,
            created_at    TEXT    NOT NULL,
            updated_at    TEXT    NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE order_items (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            order_id      INTEGER NOT NULL,
            menu_item_id  INTEGER,
            name          TEXT    NOT NULL,
            price         REAL    NOT NULL CHECK (price >= 0),
            quantity      INTEGER NOT NULL DEFAULT 1 CHECK (quantity >= 1),
            notes         TEXT,
            customizations TEXT,
            created_at    TEXT    NOT NULL,
            updated_at    TEXT    NOT NULL,
            FOREIGN KEY (order_id)     REFERENCES orders (id)
              ON DELETE CASCADE,
            FOREIGN KEY (menu_item_id) REFERENCES menu_items (id)
              ON DELETE SET NULL
          )
        ''');
        final now = DateTime.now().toIso8601String();
        await db.insert('orders', {
          'table_number': 'T-1',
          'status': 'pending',
          'total': 7.5,
          'created_at': now,
          'updated_at': now,
        });
        await db.insert('order_items', {
          'order_id': 1,
          'name': 'Green Tea',
          'price': 2.5,
          'quantity': 3,
          'created_at': now,
          'updated_at': now,
        });
        },
      ),
    );
    final legacyCount =
        (await legacy.rawQuery('SELECT COUNT(*) AS c FROM order_items'))
            .first['c'] as int;
    expect(legacyCount, 1);
    await legacy.close();

    // ---- Phase B: open through AppDatabase — the v6 migration runs. ----
    AppDatabase.overridePathForTesting = dbPath;
    final appDb = AppDatabase.instance;
    final order = await appDb.getOrder(1);
    expect(order, isNotNull, reason: 'order row must survive the migration');
    expect(order!.tableNumber, 'T-1');
    expect(order.items, hasLength(1),
        reason: 'line items must NOT be cascade-deleted by the migration');
    expect(order.items.first.name, 'Green Tea');
    expect(order.items.first.quantity, 3);

    // The widened CHECK now accepts the new `paid` status.
    final changed = await appDb.markOrderPaid(1, 'kpay');
    expect(changed, 1);
    final paid = await appDb.getOrder(1);
    expect(paid!.status, AppConstants.statusPaid);
    expect(paid.paymentMethod, 'kpay');
    expect(paid.paidAt, isNotNull);

    await appDb.close();
    AppDatabase.overridePathForTesting = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
}
