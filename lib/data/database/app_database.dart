library teashop_pos.data.database;

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
///   `menu_items` (set null – the line item keeps its name/price snapshot).
/// * Composite indexes covering the hot query paths (orders by status + time,
///   menu by category + availability, order_items by order/menu id).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static Database? _db;

  /// The open database connection, lazily initialized.
  Future<Database> get db async => _db ??= await _init();

  Future<Database> _init() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final path = join(documentsDir.path, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onDowngrade: onDatabaseDowngradeDelete,
    );
  }

  /// Runs once per connection before any schema work – the correct place to
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
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        table_number  TEXT    NOT NULL,
        status        TEXT    NOT NULL
                              CHECK (status IN ('pending','preparing','ready','served','cancelled')),
        total         REAL    NOT NULL DEFAULT 0 CHECK (total >= 0),
        customer_name TEXT,
        notes         TEXT,
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

    await _createIndexes(db);
    await _seedMenu(db);
    await _createUsersTable(db);
    await _seedUsers(db);
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
  }

  /// v1 → v2: add `updated_at` / `created_at` columns to tables that lacked
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

  /// v2 → v3: introduce the `users` table for staff accounts and seed a
  /// default waiter so the waiter login flow works out of the box.
  Future<void> _migrateToV3(Database db) async {
    await _createUsersTable(db);
    await _seedUsers(db);
  }

  /// v3 → v4: ensure the default admin account exists.  Older v3 databases
  /// were seeded with only a waiter; re-running the idempotent [_seedUsers]
  /// adds the admin without clobbering existing accounts.
  Future<void> _migrateToV4(Database db) async {
    await _seedUsers(db);
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
    _seed(batch, 'Masala Chai', 'Spiced Indian milk tea', 2.50, 'Beverages', now);
    _seed(batch, 'Ginger Lemon Tea', 'Refreshing herbal infusion', 3.00, 'Beverages', now);
    _seed(batch, 'Veg Sandwich', 'Grilled vegetable sandwich with cheese', 5.50, 'Snacks', now);
    _seed(batch, 'Chocolate Muffin', 'Freshly baked chocolate muffin', 4.00, 'Bakery', now);
    // Myanmar-language sample items – demonstrate full Unicode rendering.
    _seed(batch, 'လက်ဖက်ရည်', 'အိမ်လုပ် လက်ဖက်ရည်', 1.50, 'လက်ဖက်ရည်', now);
    _seed(batch, 'ကော်ဖီ', 'ပူနွေးသော ကော်ဖီ', 2.00, 'Beverages', now);
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
    return await database.delete('menu_items', where: 'id = ?', whereArgs: [id]);
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
    int limit = 200,
  }) async {
    final database = await db;
    final clauses = <String>[];
    final args = <Object?>[];

    if (status != null && status.isNotEmpty) {
      clauses.add('status = ?');
      args.add(status);
    }
    if (since != null && since.isNotEmpty) {
      clauses.add('created_at > ?');
      args.add(since);
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

  /// Batch-loads all line items for [orders] in a single `IN(…)` query,
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

  Future<int> updateOrderStatus(int id, String status) async {
    final database = await db;
    return await database.update(
      'orders',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
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

  /// Seeds the default admin and waiter accounts on first run.  Idempotent —
  /// each account is only inserted when its username is not already present, so
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
      String username, String password) async {
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
