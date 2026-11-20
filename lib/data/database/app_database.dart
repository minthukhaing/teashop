library teashop_pos.data.database;

import 'dart:io' show Directory, Platform;

import 'package:flutter/foundation.dart'
    show kIsWeb, visibleForTesting, debugPrint;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/auth/password_hasher.dart';
import '../../core/auth/waiter_permissions.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/myanmar_text.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/order_item.dart';
import '../models/shop_settings.dart';
import '../models/table.dart';
import '../models/user_account.dart';

/// Lightweight aggregate metrics returned by [AppDatabase.getOrderStats].
///
/// Computed in a single SQL pass so the dashboard never has to load every order
/// (and its line items) just to show a few counters.
class OrderStats {
  const OrderStats({
    required this.totalOrders,
    required this.pendingCount,
    required this.preparingCount,
    required this.readyCount,
    required this.servedCount,
    required this.cancelledCount,
    required this.todayRevenue,
  });

  final int totalOrders;
  final int pendingCount;
  final int preparingCount;
  final int readyCount;
  final int servedCount;
  final int cancelledCount;
  final double todayRevenue;

  int get activeCount => pendingCount + preparingCount + readyCount;
}

/// Singleton wrapper around the local SQLite database.
///
/// The Admin Host owns the master database; clients only access data through
/// the HTTP API exposed by [lib/server].
///
/// Schema highlights (v2):
/// * `PRAGMA foreign_keys = ON` + `journal_mode = WAL` for safe, concurrent I/O.
/// * `CHECK` constraints on price/quantity/total/available/status.
/// * Foreign keys from `order_items` to both `orders` (cascade) and
///   `menu_items` (set null -  - the line item keeps its name/price snapshot).
/// * Composite indexes covering the hot query paths (orders by status + time,
///   menu by category + availability, order_items by order/menu id).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static Database? _db;

  /// Test-only override for the database file location.
  ///
  /// On desktop the database path is derived from `%APPDATA%`/`$HOME` (see
  /// [_desktopDbPath]) which the `path_provider` fakes used in tests cannot
  /// reach - so without this override integration tests would silently read
  /// and write the developer's REAL database.  Set this in `setUpAll` before
  /// the first [db] access and reset it in `tearDownAll`.
  @visibleForTesting
  static String? overridePathForTesting;

  /// The open database connection, lazily initialized.
  Future<Database> get db async => _db ??= await _init();

  Future<Database> _init() async {
    String path;
    if (overridePathForTesting != null) {
      path = overridePathForTesting!;
    } else if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // On desktop platforms, avoid calling path_provider's method channel
      // which may throw MissingPluginException if the plugin is not registered.
      // Instead resolve the path using dart:io environment variables directly.
      path = _desktopDbPath();
    } else {
      try {
        final documentsDir = await getApplicationDocumentsDirectory();
        path = join(documentsDir.path, 'teashop_pos.db');
      } catch (e) {
        // Fallback for platforms where path_provider is unavailable or
        // throws MissingPluginException (e.g. Flutter Web).
        debugPrint('[AppDatabase] path_provider unavailable: $e');
        path = 'teashop_pos.db';
      }
    }
    final database = await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
    );

    // Always ensure the `users` table and the default admin/waiter accounts
    // exist, even when the database was already at the current schema version
    // but a previous migration failed silently or the table was emptied.
    // Both helpers are idempotent (CREATE TABLE IF NOT EXISTS / insert-if-
    // missing), so running them on every open is safe and cheap.
    await _createUsersTable(database);
    await _seedUsers(database);

    // Same idempotent guarantee for the `categories` table: created if missing
    // and seeded from the distinct categories already used by menu items.
    await _createCategoriesTable(database);

    // Same idempotent guarantee for the `tables` table: created if missing.
    // Defaults are seeded only when the table is first created (fresh install
    // or v7 migration); an Admin who deliberately removes every table is not
    // overridden on the next open.
    await _createTablesTable(database);

    return database;
  }

  /// Returns a file path for the SQLite database file on desktop platforms
  /// (Windows, Linux, macOS) **without** using the `path_provider` plugin
  /// method channel (which throws [MissingPluginException] unless the plugin
  /// is registered by the native runner).
  ///
  /// * Windows â†’ `%APPDATA%\TeashopPOS\<dbName>`
  /// * Linux/macOS â†’ `$HOME/.local/share/TeashopPOS/<dbName>`
  String _desktopDbPath() {
    final env = Platform.environment;
    String appDir;
    if (Platform.isWindows) {
      final appData = env['APPDATA'] ?? env['USERPROFILE'] ?? '.';
      appDir = join(appData, 'TeashopPOS');
    } else {
      final home = env['HOME'] ?? '.';
      appDir = join(home, '.local', 'share', 'TeashopPOS');
    }
    // Ensure directory exists synchronously (cheap; called once at start-up).
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return join(appDir, AppConstants.databaseName);
  }

  /// Runs once per connection before any schema work -  - the correct place to
  /// enable foreign keys and switch to WAL for better read/write concurrency.
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('PRAGMA journal_mode = WAL');
  }

  // -------------------------------------------------------------------------
  // Schema creation (fresh install)
  // -------------------------------------------------------------------------

  Future<void> _onCreate(Database db, int version) async {
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
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        table_number   TEXT    NOT NULL,
        status         TEXT    NOT NULL
                              CHECK (status IN ('pending','preparing','ready','served','cancelled','paid')),
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

    await _createIndexes(db);
    await _seedMenu(db);
    await _createUsersTable(db);
    await _seedUsers(db);
    await _createShopSettingsTable(db);
    await _createTablesTable(db);
    await _seedDefaultTables(db);
  }

  /// All secondary indexes, kept in one place so onCreate and onUpgrade stay
  /// in sync.
  Future<void> _createIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_items_category ON menu_items (category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_items_available ON menu_items (available)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_menu_items_category_available '
      'ON menu_items (category, available)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders (created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_orders_status_created '
      'ON orders (status, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_order_items_menu_item_id ON order_items (menu_item_id)',
    );
  }

  // -------------------------------------------------------------------------
  // Migrations
  // -------------------------------------------------------------------------

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4) {
      await _migrateToV4(db);
    }
    if (oldVersion < 5) {
      await _migrateToV5(db);
    }
    if (oldVersion < 6) {
      await _migrateToV6(db);
    }
    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
  }

  /// v1 â†’ v2: add `updated_at` / `created_at` columns to tables that lacked
  /// them and back-fill from existing data, then create the new indexes.
  Future<void> _migrateToV2(Database db) async {
    await _addColumnIfMissing(db, 'menu_items', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'orders', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'order_items', 'updated_at', 'TEXT');
    await _addColumnIfMissing(db, 'order_items', 'created_at', 'TEXT');

    final now = DateTime.now().toIso8601String();
    await db.execute(
      'UPDATE menu_items SET updated_at = created_at WHERE updated_at IS NULL',
    );
    await db.execute(
      'UPDATE orders SET updated_at = created_at WHERE updated_at IS NULL',
    );
    await db.execute(
      'UPDATE order_items SET created_at = ? WHERE created_at IS NULL',
      [now],
    );
    await db.execute(
      'UPDATE order_items SET updated_at = ? WHERE updated_at IS NULL',
      [now],
    );

    await _createIndexes(db);
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  /// v2 â†’ v3: introduce the `users` table for staff accounts and seed a
  /// default waiter so the waiter login flow works out of the box.
  Future<void> _migrateToV3(Database db) async {
    await _createUsersTable(db);
    await _seedUsers(db);
  }

  /// v3 â†’ v4: ensure the default admin account exists.  Older v3 databases
  /// were seeded with only a waiter; re-running the idempotent [_seedUsers]
  /// adds the admin without clobbering existing accounts.
  Future<void> _migrateToV4(Database db) async {
    await _seedUsers(db);
  }

  /// v4 â†’ v5: add `waiter_name` to `orders` (shown on POS vouchers) and create
  /// the `shop_settings` table (shop name/address + Gov Tax %).
  Future<void> _migrateToV5(Database db) async {
    await _addColumnIfMissing(db, 'orders', 'waiter_name', 'TEXT');
    await _createShopSettingsTable(db);
  }

  /// v5 â†’ v6: introduce the `paid` order status and payment tracking.
  ///
  /// SQLite cannot ALTER a CHECK constraint, so the `orders` table is rebuilt.
  /// Because `PRAGMA foreign_keys = ON` and `order_items` cascades on delete,
  /// simply dropping the old `orders` table would implicitly DELETE its rows
  /// and cascade-delete every line item.  To avoid that, BOTH tables are
  /// rebuilt side by side and only swapped once all rows (including line
  /// items) have been copied across:
  ///
  /// 1. create `orders_v6` (widened status CHECK + `payment_method`/`paid_at`)
  ///    and copy all order rows,
  /// 2. create `order_items_v6` referencing `orders_v6` and copy all items,
  /// 3. drop the old child table first, then the old parent (no rows are
  ///    deleted while children still reference the parent, so no cascade),
  /// 4. rename the new tables back to `orders` / `order_items` (SQLite
  ///    rewrites the FK reference to the renamed parent), and
  /// 5. recreate all indexes.
  Future<void> _migrateToV6(Database db) async {
    await db.execute('DROP TABLE IF EXISTS orders_v6');
    await db.execute('DROP TABLE IF EXISTS order_items_v6');
    await db.execute('''
      CREATE TABLE orders_v6 (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        table_number   TEXT    NOT NULL,
        status         TEXT    NOT NULL
                              CHECK (status IN ('pending','preparing','ready','served','cancelled','paid')),
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
      INSERT INTO orders_v6 (id, table_number, status, total, customer_name,
                             notes, waiter_name, payment_method, paid_at,
                             created_at, updated_at)
      SELECT id, table_number, status, total, customer_name, notes,
             waiter_name, NULL, NULL, created_at,
             COALESCE(updated_at, created_at)
      FROM orders
    ''');
    await db.execute('''
      CREATE TABLE order_items_v6 (
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
        FOREIGN KEY (order_id)     REFERENCES orders_v6 (id)
          ON DELETE CASCADE,
        FOREIGN KEY (menu_item_id) REFERENCES menu_items (id)
          ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      INSERT INTO order_items_v6 (id, order_id, menu_item_id, name, price,
                                  quantity, notes, customizations, created_at,
                                  updated_at)
      SELECT id, order_id, menu_item_id, name, price, quantity, notes,
             customizations, created_at, COALESCE(updated_at, created_at)
      FROM order_items
    ''');
    // Drop the child first, then the parent - by now nothing references
    // `orders`, so its implicit DELETE FROM cannot cascade anywhere.
    await db.execute('DROP TABLE order_items');
    await db.execute('DROP TABLE orders');
    await db.execute('ALTER TABLE orders_v6 RENAME TO orders');
    await db.execute('ALTER TABLE order_items_v6 RENAME TO order_items');
    await _createIndexes(db);
  }

  /// v6 â†’ v7: introduce the `tables` table, the canonical source of truth for
  /// the dining-table floor plan.  Existing databases get a default set of
  /// tables (T1..T12) so the Waiter tables grid keeps working out of the box;
  /// the Admin can then add, rename, activate/deactivate or remove tables
  /// from the Admin Tables screen.
  Future<void> _migrateToV7(Database db) async {
    await _createTablesTable(db);
    await _seedDefaultTables(db);
  }

  /// Creates the `tables` table if missing. Idempotent â€” safe to run on every
  /// database open.
  Future<void> _createTablesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tables (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        number      TEXT    NOT NULL UNIQUE,
        capacity    INTEGER NOT NULL DEFAULT 4
                          CHECK (capacity > 0),
        is_active   INTEGER NOT NULL DEFAULT 1
                          CHECK (is_active IN (0, 1)),
        created_at  TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tables_is_active ON tables (is_active)',
    );
  }

  /// Seeds the initial floor plan (T1..T12) only when the `tables` table is
  /// empty at creation time.  Once the Admin has configured tables this is
  /// never run again, so waiter clients always sync the Admin's real list.
  Future<void> _seedDefaultTables(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM tables'),
    );
    if (count != null && count > 0) return;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (var i = 1; i <= 12; i++) {
      batch.insert('tables', {
        'number': 'T$i',
        'capacity': 4,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
    await batch.commit(noResult: true);
  }

  /// Creates the single-row `shop_settings` table if missing and seeds the
  /// default row (`id = 1`). Idempotent -  - safe on every database open.
  Future<void> _createShopSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shop_settings (
        id               INTEGER PRIMARY KEY CHECK (id = 1),
        shop_name        TEXT    NOT NULL DEFAULT 'Teashop POS',
        shop_address     TEXT,
        gov_tax_percent  REAL    NOT NULL DEFAULT 0 CHECK (gov_tax_percent >= 0),
        updated_at       TEXT    NOT NULL
      )
    ''');
    await db.execute(
      "INSERT OR IGNORE INTO shop_settings (id, shop_name, shop_address, "
      "gov_tax_percent, updated_at) VALUES (1, 'Teashop POS', '', 0, ?)",
      [DateTime.now().toIso8601String()],
    );
  }

  /// Returns the shop profile / billing settings (never `null` -  - falls back
  /// to defaults when the row is somehow missing).
  Future<ShopSettings> getShopSettings() async {
    final database = await db;
    await _createShopSettingsTable(database);
    final maps = await database.query(
      'shop_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (maps.isEmpty) return ShopSettings();
    return ShopSettings.fromMap(maps.first);
  }

  /// Persists [settings] into the single settings row.
  Future<void> saveShopSettings(ShopSettings settings) async {
    final database = await db;
    await _createShopSettingsTable(database);
    await database.insert('shop_settings', {
      ...settings.toMap(),
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // -------------------------------------------------------------------------
  // Seeding
  // -------------------------------------------------------------------------

  Future<void> _seedMenu(Database db) async {
    final existing = await db.rawQuery('SELECT COUNT(*) AS c FROM menu_items');
    final count = (existing.first['c'] as int?) ?? 0;
    if (count != 0) return;

    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    _seed(
      batch,
      'Masala Chai',
      'Spiced Indian milk tea',
      2.50,
      'Beverages',
      now,
    );
    _seed(
      batch,
      'Ginger Lemon Tea',
      'Refreshing herbal infusion',
      3.00,
      'Beverages',
      now,
    );
    _seed(
      batch,
      'Veg Sandwich',
      'Grilled vegetable sandwich with cheese',
      5.50,
      'Snacks',
      now,
    );
    _seed(
      batch,
      'Chocolate Muffin',
      'Freshly baked chocolate muffin',
      4.00,
      'Bakery',
      now,
    );
    // Myanmar-language sample items -  - demonstrate full Unicode rendering.
    _seed(
      batch,
      'á€œá€€á€ºá€–á€€á€ºá€›á€Šá€º',
      'á€¡á€­á€™á€ºá€œá€¯á€•á€º á€œá€€á€ºá€–á€€á€ºá€›á€Šá€º',
      1.50,
      'á€œá€€á€ºá€–á€€á€ºá€›á€Šá€º',
      now,
    );
    _seed(
      batch,
      'á€€á€±á€¬á€ºá€–á€®',
      'á€•á€°á€”á€½á€±á€¸á€žá€±á€¬ á€€á€±á€¬á€ºá€–á€®',
      2.00,
      'Beverages',
      now,
    );
    await batch.commit(noResult: true);
  }

  void _seed(
    Batch batch,
    String name,
    String desc,
    double price,
    String category,
    String now,
  ) {
    batch.insert('menu_items', {
      'name': MyanmarText.normalize(name),
      'description': MyanmarText.normalizeNullable(desc),
      'price': price,
      'category': MyanmarText.normalize(category),
      'available': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  /// Creates the `categories` table if it does not exist yet and seeds it
  /// (when empty) from the distinct categories used by existing menu items.
  /// Idempotent -  - safe to run on every database open.
  Future<void> _createCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL UNIQUE,
        created_at  TEXT NOT NULL
      )
    ''');
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM categories'),
    );
    if (count == 0) {
      await db.execute(
        'INSERT OR IGNORE INTO categories (name, created_at) '
        'SELECT DISTINCT category, ? FROM menu_items',
        [DateTime.now().toIso8601String()],
      );
    }
  }

  /// All category names, sorted alphabetically. Any category that only
  /// exists on menu items (legacy data) is merged in as well.
  Future<List<String>> getCategories() async {
    final database = await db;
    final rows = await database.query('categories', orderBy: 'name ASC');
    final names = rows.map((r) => r['name'] as String).toSet();
    final itemCats = await database.rawQuery(
      'SELECT DISTINCT category FROM menu_items',
    );
    names.addAll(itemCats.map((r) => r['category'] as String));
    return names.toList()..sort();
  }

  /// Inserts a new category. Returns 0 if a category with the same
  /// (normalized) name already exists.
  Future<int> insertCategory(String name) async {
    final database = await db;
    return await database.insert('categories', {
      'name': MyanmarText.normalize(name.trim()),
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Renames a category everywhere (categories table + all menu items in it).
  /// Returns the number of affected menu items.
  Future<int> renameCategory(String oldName, String newName) async {
    final database = await db;
    final normalized = MyanmarText.normalize(newName.trim());
    return await database.transaction((txn) async {
      await txn.update(
        'categories',
        {'name': normalized},
        where: 'name = ?',
        whereArgs: [oldName],
      );
      return await txn.update(
        'menu_items',
        {
          'category': normalized,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'category = ?',
        whereArgs: [oldName],
      );
    });
  }

  /// Deletes a category and every menu item that belongs to it.
  /// Returns the number of deleted menu items.
  Future<int> deleteCategory(String name) async {
    final database = await db;
    return await database.transaction((txn) async {
      await txn.delete('categories', where: 'name = ?', whereArgs: [name]);
      return await txn.delete(
        'menu_items',
        where: 'category = ?',
        whereArgs: [name],
      );
    });
  }

  /// Number of menu items per category (used for category list badges and
  /// delete-confirmation messages).
  Future<Map<String, int>> menuItemCountsByCategory() async {
    final database = await db;
    final rows = await database.rawQuery(
      'SELECT category, COUNT(*) AS c FROM menu_items GROUP BY category',
    );
    return {
      for (final row in rows)
        row['category'] as String: (row['c'] as int? ?? 0),
    };
  }

  // -------------------------------------------------------------------------
  // Tables
  // -------------------------------------------------------------------------

  /// Returns all tables, optionally filtered to active ones only.  Ordered by
  /// table number so the floor plan is stable across clients.
  Future<List<TableModel>> getTables({bool? activeOnly}) async {
    final database = await db;
    final maps = await database.query(
      'tables',
      where: activeOnly == null ? null : 'is_active = ?',
      whereArgs: activeOnly == null ? null : [activeOnly ? 1 : 0],
      orderBy: 'number ASC',
    );
    return maps.map(TableModel.fromMap).toList();
  }

  /// Returns the table with [id], or `null` when it does not exist.
  Future<TableModel?> getTable(int id) async {
    final database = await db;
    final maps = await database.query(
      'tables',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TableModel.fromMap(maps.first);
  }

  /// Returns the table with [number], or `null` when it does not exist.
  Future<TableModel?> getTableByNumber(String number) async {
    final database = await db;
    final maps = await database.query(
      'tables',
      where: 'number = ?',
      whereArgs: [MyanmarText.normalize(number.trim())],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TableModel.fromMap(maps.first);
  }

  /// Inserts [table] and returns its new row id.  Throws on a duplicate
  /// `number` (SQLite UNIQUE constraint).
  Future<int> insertTable(TableModel table) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    return await database.insert('tables', {
      ...table.toMap(),
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Updates [table]. Returns the number of affected rows.
  Future<int> updateTable(TableModel table) async {
    if (table.id == null) return 0;
    final database = await db;
    return await database.update(
      'tables',
      {...table.toMap(), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [table.id],
    );
  }

  /// Deletes the table with [id]. Returns the number of affected rows.
  ///
  /// Callers should check [hasActiveOrdersForTable] before deleting so
  /// tables with unpaid orders are not removed accidentally.
  Future<int> deleteTable(int id) async {
    final database = await db;
    return await database.delete('tables', where: 'id = ?', whereArgs: [id]);
  }

  /// Number of unpaid (pending/preparing/ready) orders currently open at the
  /// table identified by [tableNumber].  Used to validate delete-safety.
  Future<int> countActiveOrdersForTable(String tableNumber) async {
    final database = await db;
    final result = Sqflite.firstIntValue(
      await database.rawQuery(
        '''\
        SELECT COUNT(*) AS c FROM orders
        WHERE table_number = ?
          AND status IN ('pending', 'preparing', 'ready')''',
        [MyanmarText.normalize(tableNumber.trim())],
      ),
    );
    return result ?? 0;
  }

  /// Whether [tableNumber] currently has at least one unpaid order.
  Future<bool> hasActiveOrdersForTable(String tableNumber) async =>
      (await countActiveOrdersForTable(tableNumber)) > 0;

  // -------------------------------------------------------------------------
  // Menu items
  // -------------------------------------------------------------------------

  Future<List<MenuItem>> getMenuItems({bool? available}) async {
    final database = await db;
    final maps = await database.query(
      'menu_items',
      where: available == null ? null : 'available = ?',
      whereArgs: available == null ? null : [available ? 1 : 0],
      orderBy: 'category ASC, name ASC',
    );
    return maps.map(MenuItem.fromMap).toList();
  }

  Future<MenuItem?> getMenuItem(int id) async {
    final database = await db;
    final maps = await database.query(
      'menu_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return MenuItem.fromMap(maps.first);
  }

  Future<List<MenuItem>> searchMenuItems(String query) async {
    final database = await db;
    final like = '%${MyanmarText.normalize(query.trim())}%';
    final maps = await database.query(
      'menu_items',
      where: 'name LIKE ? OR category LIKE ? OR description LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'category ASC, name ASC',
    );
    return maps.map(MenuItem.fromMap).toList();
  }

  Future<int> insertMenuItem(MenuItem item) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    return await database.insert('menu_items', {
      ...item.toMap(),
      'id': null,
      'created_at': (item.createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': now,
    });
  }

  Future<int> updateMenuItem(MenuItem item) async {
    if (item.id == null) return 0;
    final database = await db;
    return await database.update(
      'menu_items',
      {
        ...item.toMap(),
        'id': item.id,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteMenuItem(int id) async {
    final database = await db;
    return await database.delete(
      'menu_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> toggleMenuItemAvailability(int id, bool available) async {
    final database = await db;
    return await database.update(
      'menu_items',
      {
        'available': available ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> bulkInsertMenuItems(List<MenuItem> items) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    await database.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('menu_items', {
          ...item.toMap(),
          'id': null,
          'created_at': (item.createdAt ?? DateTime.now()).toIso8601String(),
          'updated_at': now,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  // -------------------------------------------------------------------------
  // Orders
  // -------------------------------------------------------------------------

  Future<List<Order>> getOrders({
    String? status,
    String? since,
    bool unpaidOnly = false,
    int limit = 200,
  }) async {
    final database = await db;
    final clauses = <String>[];
    final args = <Object?>[];

    if (status != null && status.isNotEmpty) {
      clauses.add('LOWER(status) = ?');
      args.add(status.trim().toLowerCase());
    }
    if (since != null && since.isNotEmpty) {
      clauses.add('created_at > ?');
      args.add(since);
    }
    if (unpaidOnly) {
      // Unpaid bills: only active orders (pending/preparing/ready), matched
      // case-insensitively so mixed-case rows are still returned. Paid,
      // served and cancelled orders are excluded.
      final placeholders = List.filled(
        AppConstants.unpaidStatuses.length,
        '?',
      ).join(', ');
      clauses.add('LOWER(status) IN ($placeholders)');
      args.addAll(AppConstants.unpaidStatuses.map((s) => s.toLowerCase()));
    }

    final maps = await database.query(
      'orders',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    if (maps.isEmpty) return [];

    final orders = maps.map(Order.fromMap).toList();
    await _attachOrderItems(database, orders);
    return orders;
  }

  Future<Order?> getOrder(int id) async {
    final database = await db;
    final maps = await database.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final orders = [Order.fromMap(maps.first)];
    await _attachOrderItems(database, orders);
    return orders.first;
  }

  /// Batch-loads all line items for [orders] in a single `IN( - )` query,
  /// eliminating the N+1 problem where each order fetched its items separately.
  Future<void> _attachOrderItems(Database database, List<Order> orders) async {
    final ids = orders.where((o) => o.id != null).map((o) => o.id!).toList();
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(', ');
    final itemMaps = await database.query(
      'order_items',
      where: 'order_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'order_id ASC, id ASC',
    );

    final byOrder = <int, List<OrderItem>>{};
    for (final map in itemMaps) {
      final orderId = map['order_id'] as int?;
      if (orderId == null) continue;
      byOrder.putIfAbsent(orderId, () => []).add(OrderItem.fromMap(map));
    }

    for (var i = 0; i < orders.length; i++) {
      final items = byOrder[orders[i].id] ?? const <OrderItem>[];
      orders[i] = orders[i].copyWith(items: items);
    }
  }

  Future<int> insertOrder(Order order) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    return await database.transaction((txn) async {
      final orderId = await txn.insert('orders', {
        ...order.toMap(),
        'id': null,
        'created_at': (order.createdAt ?? DateTime.now()).toIso8601String(),
        'updated_at': now,
      });

      if (order.items.isNotEmpty) {
        final batch = txn.batch();
        for (final item in order.items) {
          batch.insert('order_items', {
            ...item.toMap(),
            'id': null,
            'order_id': orderId,
            'created_at': now,
            'updated_at': now,
          });
        }
        await batch.commit(noResult: true);
      }
      return orderId;
    });
  }

  /// Finds an existing active (unpaid) order for [tableNumber], if any.
  Future<Order?> getActiveOrderByTable(String tableNumber) async {
    final database = await db;
    final placeholders = List.filled(
      AppConstants.unpaidStatuses.length,
      '?',
    ).join(', ');
    final maps = await database.query(
      'orders',
      where: 'table_number = ? AND LOWER(status) IN ($placeholders)',
      whereArgs: [
        tableNumber,
        ...AppConstants.unpaidStatuses.map((s) => s.toLowerCase()),
      ],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final orders = [Order.fromMap(maps.first)];
    await _attachOrderItems(database, orders);
    return orders.first;
  }

  /// Inserts a new order OR appends its items to an existing active (unpaid)
  /// order for the same table.  Returns the (possibly updated) order so callers
  /// keep the same order id instead of creating a duplicate bill.
  Future<Order> insertOrAppendOrder(Order order) async {
    final existing = await getActiveOrderByTable(order.tableNumber);

    if (existing != null && existing.id != null) {
      // Merge quantities for items that already exist on the bill; otherwise
      // append as new line items.
      final merged = <OrderItem>[...existing.items];
      for (final newItem in order.items) {
        final idx = merged.indexWhere(
          (it) =>
              (it.menuItemId != null && it.menuItemId == newItem.menuItemId) ||
              (it.menuItemId == null &&
                  it.name == newItem.name &&
                  it.price == newItem.price),
        );
        if (idx >= 0) {
          merged[idx] = merged[idx].copyWith(
            quantity: merged[idx].quantity + newItem.quantity,
          );
        } else {
          merged.add(newItem);
        }
      }
      final total = merged.fold<double>(0, (s, it) => s + it.subtotal);
      final updated = existing.copyWith(items: merged, total: total);
      await updateOrder(updated);
      final saved = await getOrder(existing.id!);
      return saved ?? updated.copyWith(id: existing.id);
    }

    final id = await insertOrder(order);
    final saved = await getOrder(id);
    return saved ?? order.copyWith(id: id);
  }

  Future<int> updateOrderStatus(int id, String status) async {
    final database = await db;
    return await database.update(
      'orders',
      {'status': status, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marks an order as PAID at checkout, recording HOW it was settled
  /// (e.g. `cash`, `kpay`) and WHEN.  Returns the number of updated rows
  /// (0 when the order does not exist).
  Future<int> markOrderPaid(int id, String paymentMethod) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    return await database.update(
      'orders',
      {
        'status': AppConstants.statusPaid,
        'payment_method': MyanmarText.normalize(paymentMethod),
        'paid_at': now,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Replaces an existing order (header fields + all line items) in a single
  /// transaction.  The total is recomputed from the line items so it can never
  /// drift from the actual item sub-totals.  Returns the number of updated
  /// order rows (0 when the order does not exist).
  Future<int> updateOrder(Order order) async {
    final database = await db;
    final id = order.id;
    if (id == null) return 0;
    final now = DateTime.now().toIso8601String();
    final total = order.items.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );

    return await database.transaction((txn) async {
      final updated = await txn.update(
        'orders',
        {...order.toMap(), 'total': total, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) return 0;

      // Replace the line items wholesale (cascade FK removes the old rows).
      await txn.delete('order_items', where: 'order_id = ?', whereArgs: [id]);
      if (order.items.isNotEmpty) {
        final batch = txn.batch();
        for (final item in order.items) {
          batch.insert('order_items', {
            ...item.toMap(),
            'id': null,
            'order_id': id,
            'created_at': now,
            'updated_at': now,
          });
        }
        await batch.commit(noResult: true);
      }
      return updated;
    });
  }

  Future<int> deleteOrder(int id) async {
    final database = await db;
    return await database.delete('orders', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // Aggregates
  // -------------------------------------------------------------------------

  /// Dashboard counters and today's revenue, computed in two SQL queries
  /// instead of loading every order + line item into memory.
  Future<OrderStats> getOrderStats() async {
    final database = await db;

    final statusRows = await database.rawQuery(
      'SELECT status, COUNT(*) AS c FROM orders GROUP BY status',
    );
    final counts = <String, int>{
      for (final row in statusRows)
        row['status'] as String: (row['c'] as int?) ?? 0,
    };

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfTomorrow = startOfDay.add(const Duration(days: 1));
    final revenueRows = await database.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS r FROM orders '
      'WHERE status != ? AND created_at >= ? AND created_at < ?',
      [
        AppConstants.statusCancelled,
        startOfDay.toIso8601String(),
        startOfTomorrow.toIso8601String(),
      ],
    );

    final total = counts.values.fold<int>(0, (s, v) => s + v);
    final revenue = (revenueRows.first['r'] as num?)?.toDouble() ?? 0;

    return OrderStats(
      totalOrders: total,
      pendingCount: counts[AppConstants.statusPending] ?? 0,
      preparingCount: counts[AppConstants.statusPreparing] ?? 0,
      readyCount: counts[AppConstants.statusReady] ?? 0,
      servedCount: counts[AppConstants.statusServed] ?? 0,
      cancelledCount: counts[AppConstants.statusCancelled] ?? 0,
      todayRevenue: revenue,
    );
  }

  // -------------------------------------------------------------------------
  // Users (staff accounts)
  // -------------------------------------------------------------------------

  Future<void> _createUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        username      TEXT    NOT NULL UNIQUE,
        password_hash TEXT    NOT NULL,
        role          TEXT    NOT NULL CHECK (role IN ('admin','waiter')),
        display_name  TEXT,
        permissions   TEXT    NOT NULL DEFAULT '[]',
        active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
        created_at    TEXT    NOT NULL,
        updated_at    TEXT    NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_users_username ON users (username)',
    );
  }

  /// Seeds the default admin and waiter accounts on first run.  Idempotent - /// each account is only inserted when its username is not already present, so
  /// re-running (e.g. from a migration) never clobbers customised credentials.
  Future<void> _seedUsers(Database db) async {
    final now = DateTime.now().toIso8601String();

    await _seedUserIfMissing(
      db,
      username: 'admin',
      password: 'admin123',
      role: 'admin',
      displayName: 'Administrator',
      permissions: WaiterPermissions.all,
      now: now,
    );

    await _seedUserIfMissing(
      db,
      username: 'waiter',
      password: 'waiter123',
      role: 'waiter',
      displayName: 'Default Waiter',
      permissions: WaiterPermissions.defaultPermissions,
      now: now,
    );
  }

  /// Inserts a single user row when the username is not already taken.
  Future<void> _seedUserIfMissing(
    Database db, {
    required String username,
    required String password,
    required String role,
    required String displayName,
    required List<String> permissions,
    required String now,
  }) async {
    final existing = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM users WHERE username = ?',
      [username],
    );
    if ((existing.first['c'] as int?) != 0) return;
    await db.insert('users', {
      'username': username,
      'password_hash': PasswordHasher.hash(password),
      'role': role,
      'display_name': displayName,
      'permissions': WaiterPermissions.encode(permissions),
      'active': 1,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Returns all user accounts, optionally filtered by role.
  Future<List<UserAccount>> getUsers({String? role}) async {
    final database = await db;
    final maps = await database.query(
      'users',
      where: role == null ? null : 'role = ?',
      whereArgs: role == null ? null : [role],
      orderBy: 'username ASC',
    );
    return maps.map(UserAccount.fromMap).toList();
  }

  /// Validates credentials and returns the account on success, or `null` when
  /// the username is unknown, the password is wrong, or the account is off.
  Future<UserAccount?> authenticateUser(
    String username,
    String password,
  ) async {
    final database = await db;
    final maps = await database.query(
      'users',
      where: 'username = ? AND active = 1',
      whereArgs: [username.trim()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    final storedHash = maps.first['password_hash'] as String;
    if (!PasswordHasher.verify(password, storedHash)) return null;
    return UserAccount.fromMap(maps.first);
  }

  /// Creates a new user. [password] is hashed before storage. Throws on a
  /// duplicate username (SQLite UNIQUE constraint).
  Future<int> insertUser({
    required String username,
    required String password,
    required String role,
    String? displayName,
    required List<String> permissions,
    bool active = true,
  }) async {
    final database = await db;
    final now = DateTime.now().toIso8601String();
    return await database.insert('users', {
      'username': username.trim(),
      'password_hash': PasswordHasher.hash(password),
      'role': role,
      'display_name': displayName,
      'permissions': WaiterPermissions.encode(permissions),
      'active': active ? 1 : 0,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Updates the editable fields of a user (not the password).
  Future<int> updateUser(UserAccount user) async {
    if (user.id == null) return 0;
    final database = await db;
    return await database.update(
      'users',
      {
        'display_name': user.displayName,
        'permissions': WaiterPermissions.encode(user.permissions),
        'active': user.active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  /// Replaces a user's password (hashed).
  Future<int> updateUserPassword(int id, String newPassword) async {
    final database = await db;
    return await database.update(
      'users',
      {
        'password_hash': PasswordHasher.hash(newPassword),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Toggles the active flag.
  Future<int> toggleUserActive(int id, bool active) async {
    final database = await db;
    return await database.update(
      'users',
      {
        'active': active ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteUser(int id) async {
    final database = await db;
    return await database.delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> close() async {
    final database = _db;
    if (database != null) {
      await database.close();
      _db = null;
    }
  }
}
