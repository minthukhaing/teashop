// Server integration test.
//
// Boots the REAL AppDatabase (schema + seed menu) and the REAL AppServer using
// the FFI SQLite factory and a fake path_provider platform, then exercises every
// REST endpoint over HTTP.  Runs on Windows desktop without an Android emulator.
//
// Run with:  flutter test test/server_integration_test.dart
library teashop_pos.test.server_integration_test;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:teashop_pos/client/waiter_api_service.dart';
import 'package:teashop_pos/core/auth/admin_auth.dart';
import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/core/network/local_ip.dart';
import 'package:teashop_pos/core/utils/myanmar_text.dart';
import 'package:teashop_pos/data/database/app_database.dart';
import 'package:teashop_pos/data/models/table.dart';
import 'package:teashop_pos/server/app_server.dart';

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
  late final AppServer server;
  late final AppDatabase db;
  const port = 8081;
  final baseUrl = 'http://127.0.0.1:$port';
  final menuUrl = '$baseUrl${AppConstants.apiPrefix}${AppConstants.menuEndpoint}';
  final ordersUrl =
      '$baseUrl${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}';
  final tablesUrl =
      '$baseUrl${AppConstants.apiPrefix}${AppConstants.tablesEndpoint}';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Remove the test framework's HttpOverrides mock so real HTTP requests
    // to the in-process server actually go through dart:io's HttpClient.
    HttpOverrides.global = null;

    // FFI SQLite so sqflite works on the host without a native plugin.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Fresh temp dir for the database file.
    tempDir = Directory.systemTemp.createTempSync('teashop_server_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    // On desktop AppDatabase resolves the DB path from %APPDATA%/$HOME which
    // the fake path_provider above cannot reach — point it at the temp dir
    // explicitly so the suite never touches the developer's real database.
    AppDatabase.overridePathForTesting =
        p.join(tempDir.path, AppConstants.databaseName);

    db = AppDatabase.instance;
    server = AppServer.withDb(db);
    await server.start(port: port, address: InternetAddress.loopbackIPv4);
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    AppDatabase.overridePathForTesting = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Health
  // -------------------------------------------------------------------------

  test('GET /health returns status ok', () async {
    final response =
        await http.get(Uri.parse('$baseUrl${AppConstants.healthEndpoint}'));
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    expect(body['status'], 'ok');
    expect(body['server'], 'teashop-pos-admin');
  });

  // -------------------------------------------------------------------------
  // Menu CRUD
  // -------------------------------------------------------------------------

  test('GET /api/menu returns seeded items (>= 4)', () async {
    final response = await http.get(Uri.parse(menuUrl));
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    expect(body.length, greaterThanOrEqualTo(4));
    for (final item in body) {
      final m = item as Map<String, dynamic>;
      expect(m['name'], isA<String>());
      expect(m['price'], isA<num>());
      expect(m['category'], isA<String>());
    }
  });

  test('POST /api/menu creates a new item and returns 201', () async {
    final response = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'Test Espresso',
        'description': 'Double shot',
        'price': 3.50,
        'category': 'Beverages',
        'available': true,
      }),
    );
    expect(response.statusCode, 201);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    expect(body['name'], 'Test Espresso');
    expect(body['price'], 3.50);
    expect(body['id'], isNotNull);
  });

  test('PUT /api/menu/:id updates an existing item', () async {
    final createResponse = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'Latte Original',
        'price': 4.00,
        'category': 'Beverages',
        'available': true,
      }),
    );
    final created = jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>;
    final id = created['id'] as int;

    final updateResponse = await http.put(
      Uri.parse('$menuUrl/$id'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'Latte Updated',
        'price': 4.50,
        'available': false,
      }),
    );
    expect(updateResponse.statusCode, 200);
    final updated = jsonDecode(utf8.decode(updateResponse.bodyBytes)) as Map<String, dynamic>;
    expect(updated['name'], 'Latte Updated');
    expect(updated['price'], 4.50);
    expect(updated['available'], false);
  });

  test('DELETE /api/menu/:id removes an item', () async {
    final createResponse = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'Delete Me',
        'price': 1.00,
        'category': 'Other',
        'available': true,
      }),
    );
    final created = jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>;
    final id = created['id'] as int;

    final deleteResponse = await http.delete(Uri.parse('$menuUrl/$id'));
    expect(deleteResponse.statusCode, 200);
    final body = jsonDecode(utf8.decode(deleteResponse.bodyBytes)) as Map<String, dynamic>;
    expect(body['success'], true);
  });

  test('POST /api/menu with negative price returns 400 (CHECK constraint)',
      () async {
    final response = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'Bad Item',
        'price': -5.00,
        'category': 'Other',
        'available': true,
      }),
    );
    expect(response.statusCode, 400);
  });

  // -------------------------------------------------------------------------
  // Order CRUD
  // -------------------------------------------------------------------------

  test('POST /api/orders creates an order with line items', () async {
    // On desktop the server runs against the real user database, so the
    // seeded menu ids may have been customised.  Pull two live menu items
    // through the API instead of hard-coding ids 1 and 2.
    final menuResponse = await http.get(Uri.parse(menuUrl));
    expect(menuResponse.statusCode, 200);
    final menu = (jsonDecode(utf8.decode(menuResponse.bodyBytes)) as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(menu.length, greaterThanOrEqualTo(2),
        reason: 'Need at least two menu items for this test.');
    final first = menu[0];
    final second = menu[1];
    final firstPrice = (first['price'] as num).toDouble();
    final secondPrice = (second['price'] as num).toDouble();

    final response = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': 'T-5',
        'customerName': 'John Doe',
        'notes': 'Window seat',
        'items': [
          {
            'menuItemId': first['id'],
            'name': first['name'],
            'price': firstPrice,
            'quantity': 2,
            'notes': 'extra hot',
          },
          {
            'menuItemId': second['id'],
            'name': second['name'],
            'price': secondPrice,
            'quantity': 1,
          },
        ],
      }),
    );
    expect(response.statusCode, 201, reason: response.body);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    expect(body['tableNumber'], 'T-5');
    expect(body['status'], AppConstants.statusPending);
    expect(body['total'], 2 * firstPrice + secondPrice);
    expect(body['id'], isNotNull);
    final items = body['items'] as List<dynamic>;
    expect(items.length, 2);
    expect((items[0] as Map<String, dynamic>)['name'], first['name']);
    expect((items[0] as Map<String, dynamic>)['menuItemId'], first['id']);
  });

  test('GET /api/orders returns created orders with items', () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': 'T-10',
        'items': [
          {'name': 'Green Tea', 'price': 2.00, 'quantity': 3},
        ],
      }),
    );
    expect(createResponse.statusCode, 201, reason: createResponse.body);
    final createdId =
        (jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>)['id'];

    final response = await http.get(Uri.parse(ordersUrl));
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    expect(body, isNotEmpty);
    // Find the order this test just created (the list also contains rows from
    // earlier runs of the suite, so do not rely on list position).
    final created = body.firstWhere(
      (o) => (o as Map<String, dynamic>)['id'] == createdId,
      orElse: () => fail('created order $createdId not returned by GET'),
    ) as Map<String, dynamic>;
    expect(created['items'], isA<List>());
    expect((created['items'] as List).length, greaterThanOrEqualTo(1));
  });

  test('GET /api/orders?status=pending filters by status', () async {
    final response = await http.get(
        Uri.parse('$ordersUrl?status=${AppConstants.statusPending}'));
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    for (final order in body) {
      expect((order as Map<String, dynamic>)['status'],
          AppConstants.statusPending);
    }
  });

  test('PATCH /api/orders/:id with status=paid records the payment method',
      () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': 'T-30',
        'items': [
          {'name': 'Latte', 'price': 3.00, 'quantity': 2},
        ],
      }),
    );
    expect(createResponse.statusCode, 201, reason: createResponse.body);
    final id = (jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>)['id'];

    final payResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'status': AppConstants.statusPaid,
        'paymentMethod': 'kpay',
      }),
    );
    expect(payResponse.statusCode, 200, reason: payResponse.body);
    final payBody = jsonDecode(utf8.decode(payResponse.bodyBytes)) as Map<String, dynamic>;
    expect(payBody['success'], true);
    expect(payBody['status'], AppConstants.statusPaid);
    expect(payBody['paymentMethod'], 'kpay');

    // The paid order no longer shows up on the unpaid list…
    final unpaidResponse =
        await http.get(Uri.parse('$ordersUrl?unpaid=true'));
    final unpaidBody = jsonDecode(utf8.decode(unpaidResponse.bodyBytes)) as List<dynamic>;
    expect(
      unpaidBody.where(
          (o) => (o as Map<String, dynamic>)['id'] == id),
      isEmpty,
    );

    // …and the stored row carries the payment method + timestamp.
    final paidOrder = await db.getOrder(id as int);
    expect(paidOrder!.status, AppConstants.statusPaid);
    expect(paidOrder.paymentMethod, 'kpay');
    expect(paidOrder.paidAt, isNotNull);
  });

  test('PATCH /api/orders/:id advances status pending -> preparing -> ready',
      () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': 'T-20',
        'items': [
          {'name': 'Coffee', 'price': 2.50, 'quantity': 1},
        ],
      }),
    );
    final created = jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>;
    final id = created['id'] as int;

    var patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'status': AppConstants.statusPreparing}),
    );
    expect(patchResponse.statusCode, 200);
    expect(
        (jsonDecode(utf8.decode(patchResponse.bodyBytes)) as Map<String, dynamic>)['status'],
        AppConstants.statusPreparing);

    patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'status': AppConstants.statusReady}),
    );
    expect(patchResponse.statusCode, 200);
    expect(
        (jsonDecode(utf8.decode(patchResponse.bodyBytes)) as Map<String, dynamic>)['status'],
        AppConstants.statusReady);
  });

  test('PATCH /api/orders/:id with invalid status returns 400', () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': 'T-40',
        'items': [
          {'name': 'Water', 'price': 1.00, 'quantity': 1},
        ],
      }),
    );
    final created = jsonDecode(utf8.decode(createResponse.bodyBytes)) as Map<String, dynamic>;
    final id = created['id'] as int;

    final patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'status': 'invalid_status'}),
    );
    expect(patchResponse.statusCode, 400);
  });

  // -------------------------------------------------------------------------
  // Auth (waiter login)
  // -------------------------------------------------------------------------

  test('POST /api/auth/login with valid waiter credentials returns 200',
      () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': 'waiter', 'password': 'waiter123'}),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    expect(body['success'], true);
    final user = body['user'] as Map<String, dynamic>;
    expect(user['username'], 'waiter');
    expect(user['role'], 'waiter');
    final perms = user['permissions'] as List<dynamic>;
    expect(perms, contains('take_orders'));
    expect(perms, contains('view_orders'));
  });

  test('POST /api/auth/login with wrong password returns 401', () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': 'waiter', 'password': 'wrong'}),
    );
    expect(response.statusCode, 401);
  });

  test('POST /api/auth/login with unknown user returns 401', () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': 'nobody', 'password': 'x'}),
    );
    expect(response.statusCode, 401);
  });

  test('POST /api/auth/login with admin credentials returns admin role',
      () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'username': 'admin', 'password': 'admin123'}),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    expect(body['success'], true);
    final user = body['user'] as Map<String, dynamic>;
    expect(user['role'], 'admin');
  });

  test('AdminAuth login + changePassword persists across sessions', () async {
    final auth = AdminAuth.instance;
    expect(await auth.login('admin', 'admin123'), true);
    expect(auth.isLoggedIn, true);
    expect(await auth.changePassword('admin123', 'newpass456'), true);
    auth.logout();
    // Old password no longer works.
    expect(await auth.login('admin', 'admin123'), false);
    // New password works.
    expect(await auth.login('admin', 'newpass456'), true);
    // Restore default so other tests are unaffected.
    expect(await auth.changePassword('newpass456', 'admin123'), true);
    auth.logout();
  });

  // -------------------------------------------------------------------------
  // CORS
  // -------------------------------------------------------------------------

  test('OPTIONS preflight returns CORS headers', () async {
    final request = http.Request('OPTIONS', Uri.parse(menuUrl));
    final response = await http.Client().send(request);
    expect(response.statusCode, 200);
    expect(response.headers['access-control-allow-origin'], '*');
    expect(response.headers['access-control-allow-methods'], contains('GET'));
    expect(response.headers['access-control-allow-methods'], contains('POST'));
  });

  // -------------------------------------------------------------------------
  // Tables — Admin SQLite is the source of truth for the Waiter floor plan
  // -------------------------------------------------------------------------

  test('GET /api/tables mirrors the Admin database and filters inactive tables',
      () async {
    const inactiveNumber = 'API-INACTIVE';
    final id = await db.insertTable(TableModel(
      number: inactiveNumber,
      capacity: 2,
      isActive: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    try {
      final allResponse = await http.get(Uri.parse(tablesUrl));
      expect(allResponse.statusCode, 200);
      final all = jsonDecode(utf8.decode(allResponse.bodyBytes)) as List<dynamic>;
      expect(all.map((t) => t['number']), contains(inactiveNumber));

      final activeResponse =
          await http.get(Uri.parse('$tablesUrl?active=true'));
      expect(activeResponse.statusCode, 200);
      final active = jsonDecode(utf8.decode(activeResponse.bodyBytes)) as List<dynamic>;
      expect(active.map((t) => t['number']), isNot(contains(inactiveNumber)));
      for (final table in active) {
        expect(table['isActive'], isTrue);
      }
    } finally {
      await db.deleteTable(id);
    }
  });

  test('WaiterApiService.fetchTables reflects Admin table add/delete via API',
      () async {
    final api = WaiterApiService(baseUrl: baseUrl);
    addTearDown(api.dispose);

    const number = 'API-SYNC-1';
    final before = await api.fetchTables();
    expect(before.map((t) => t.number), isNot(contains(number)));

    final create = await http.post(
      Uri.parse(tablesUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'number': number, 'capacity': 6, 'isActive': true}),
    );
    expect(create.statusCode, 201);
    final created = jsonDecode(utf8.decode(create.bodyBytes)) as Map<String, dynamic>;

    try {
      final afterAdd = await api.fetchTables();
      expect(afterAdd.length, before.length + 1);
      final added = afterAdd.firstWhere((t) => t.number == number);
      expect(added.capacity, 6);
      expect(added.isActive, isTrue);
    } finally {
      final delete = await http.delete(Uri.parse('$tablesUrl/${created['id']}'));
      expect(delete.statusCode, 200);
    }

    final afterDelete = await api.fetchTables();
    expect(afterDelete.length, before.length);
    expect(afterDelete.map((t) => t.number), isNot(contains(number)));
  });

  test('POST /api/tables rejects duplicate numbers', () async {
    const number = 'API-DUPLICATE';
    final create = await http.post(
      Uri.parse(tablesUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'number': number, 'capacity': 4}),
    );
    expect(create.statusCode, 201);
    final created = jsonDecode(utf8.decode(create.bodyBytes)) as Map<String, dynamic>;
    addTearDown(() async {
      await http.delete(Uri.parse('$tablesUrl/${created['id']}'));
    });

    final duplicate = await http.post(
      Uri.parse(tablesUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'number': number, 'capacity': 6}),
    );
    expect(duplicate.statusCode, 409);
    final body = jsonDecode(utf8.decode(duplicate.bodyBytes)) as Map<String, dynamic>;
    expect(body['error'], contains('already exists'));

    final api = WaiterApiService(baseUrl: baseUrl);
    addTearDown(api.dispose);
    final tables = await api.fetchTables();
    expect(tables.where((t) => t.number == number).length, 1);
    expect(tables.firstWhere((t) => t.number == number).capacity, 4);
  });

  test('DELETE /api/tables refuses a table with unpaid orders', () async {
    const number = 'API-ACTIVE';
    final create = await http.post(
      Uri.parse(tablesUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({'number': number, 'capacity': 4}),
    );
    expect(create.statusCode, 201);
    final table = jsonDecode(utf8.decode(create.bodyBytes)) as Map<String, dynamic>;

    final orderResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'tableNumber': number,
        'items': [
          {'name': 'Chai', 'price': 2.0, 'quantity': 1},
        ],
      }),
    );
    expect(orderResponse.statusCode, 201);
    final order = jsonDecode(utf8.decode(orderResponse.bodyBytes)) as Map<String, dynamic>;

    final refused = await http.delete(Uri.parse('$tablesUrl/${table['id']}'));
    expect(refused.statusCode, 409);
    final body = jsonDecode(utf8.decode(refused.bodyBytes)) as Map<String, dynamic>;
    expect(body['error'], contains(number));

    // Clearing the unpaid order makes the table removable.
    final cleared = await http.delete(Uri.parse('$ordersUrl/${order['id']}'));
    expect(cleared.statusCode, 200);
    final removed = await http.delete(Uri.parse('$tablesUrl/${table['id']}'));
    expect(removed.statusCode, 200);
  });

  test('Burmese text round-trips as UTF-8 and NFC through the API', () async {
    final api = WaiterApiService(baseUrl: baseUrl);
    addTearDown(api.dispose);

    // "A" + combining grave accent (NFD) must arrive as NFC "À".
    final create = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json; charset=utf-8'},
      body: jsonEncode({
        'name': 'A\u0300',
        'description': 'လက်ဖက်ရည်',
        'price': 1.5,
        'category': 'Beverages',
      }),
    );
    expect(create.statusCode, 201);
    final created =
        jsonDecode(utf8.decode(create.bodyBytes)) as Map<String, dynamic>;
    expect(created['name'], '\u00C0');
    final id = created['id'] as int;
    addTearDown(() async {
      await http.delete(Uri.parse('$menuUrl/$id'));
    });

    final fetched = (await api.fetchMenu()).firstWhere((m) => m.id == id);
    expect(fetched.name, '\u00C0');
    expect(fetched.description, MyanmarText.normalize('လက်ဖက်ရည်'));
  });

  // -------------------------------------------------------------------------
  // LAN reachability test
  // -------------------------------------------------------------------------

  test('server reachable over the local LAN IP', () async {
    final lanIp = await LocalIpResolver.getLocalIpAddress();
    if (lanIp == null) {
      // No LAN adapter on this machine (e.g. CI with loopback only).
      return;
    }
    const lanPort = 8082;
    final lanServer = AppServer.withDb(db);
    await lanServer.start(
      port: lanPort,
      address: InternetAddress.anyIPv4,
    );

    try {
      // Health check over the LAN IP.
      final healthResponse = await http.get(
        Uri.parse('http://$lanIp:$lanPort${AppConstants.healthEndpoint}'),
      );
      expect(healthResponse.statusCode, 200);
      final healthBody =
          jsonDecode(utf8.decode(healthResponse.bodyBytes)) as Map<String, dynamic>;
      expect(healthBody['status'], 'ok');

      // Fetch menu over the LAN IP.
      final menuResponse = await http.get(
        Uri.parse(
            'http://$lanIp:$lanPort${AppConstants.apiPrefix}${AppConstants.menuEndpoint}'),
      );
      expect(menuResponse.statusCode, 200);
      final menuBody = jsonDecode(utf8.decode(menuResponse.bodyBytes)) as List<dynamic>;
      expect(menuBody.length, greaterThanOrEqualTo(4));

      // Submit an order over the LAN IP.
      final orderResponse = await http.post(
        Uri.parse(
            'http://$lanIp:$lanPort${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'tableNumber': 'LAN-1',
          'items': [
            {'name': 'Chai', 'price': 2.00, 'quantity': 2},
          ],
        }),
      );
      expect(orderResponse.statusCode, 201);
      final orderBody =
          jsonDecode(utf8.decode(orderResponse.bodyBytes)) as Map<String, dynamic>;
      expect(orderBody['tableNumber'], 'LAN-1');
      expect(orderBody['total'], 4.0);
    } finally {
      await lanServer.stop();
    }
  });
}
