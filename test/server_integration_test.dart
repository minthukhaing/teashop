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
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:teashop_pos/core/auth/admin_auth.dart';
import 'package:teashop_pos/core/constants/app_constants.dart';
import 'package:teashop_pos/data/database/app_database.dart';
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

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Remove the test framework's HttpOverrides mock so real HTTP requests
    // to the in-process server actually go through dart:io's HttpClient.
    HttpOverrides.global = null;

    // FFI SQLite so sqflite works on the host without a native plugin.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Fresh temp dir for the database file.
    tempDir = Directory(r'c:\Users\admin\Desktop\teashopmobile\build\server_test');
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    tempDir.createSync(recursive: true);
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);

    db = AppDatabase.instance;
    server = AppServer.withDb(db);
    await server.start(port: port, address: InternetAddress.loopbackIPv4);
  });

  tearDownAll(() async {
    await server.stop();
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // -------------------------------------------------------------------------
  // Health
  // -------------------------------------------------------------------------

  test('GET /health returns status ok', () async {
    final response =
        await http.get(Uri.parse('$baseUrl${AppConstants.healthEndpoint}'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['status'], 'ok');
    expect(body['server'], 'teashop-pos-admin');
  });

  // -------------------------------------------------------------------------
  // Menu CRUD
  // -------------------------------------------------------------------------

  test('GET /api/menu returns seeded items (>= 4)', () async {
    final response = await http.get(Uri.parse(menuUrl));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List<dynamic>;
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Test Espresso',
        'description': 'Double shot',
        'price': 3.50,
        'category': 'Beverages',
        'available': true,
      }),
    );
    expect(response.statusCode, 201);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['name'], 'Test Espresso');
    expect(body['price'], 3.50);
    expect(body['id'], isNotNull);
  });

  test('PUT /api/menu/:id updates an existing item', () async {
    final createResponse = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Latte Original',
        'price': 4.00,
        'category': 'Beverages',
        'available': true,
      }),
    );
    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final id = created['id'] as int;

    final updateResponse = await http.put(
      Uri.parse('$menuUrl/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Latte Updated',
        'price': 4.50,
        'available': false,
      }),
    );
    expect(updateResponse.statusCode, 200);
    final updated = jsonDecode(updateResponse.body) as Map<String, dynamic>;
    expect(updated['name'], 'Latte Updated');
    expect(updated['price'], 4.50);
    expect(updated['available'], false);
  });

  test('DELETE /api/menu/:id removes an item', () async {
    final createResponse = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': 'Delete Me',
        'price': 1.00,
        'category': 'Other',
        'available': true,
      }),
    );
    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final id = created['id'] as int;

    final deleteResponse = await http.delete(Uri.parse('$menuUrl/$id'));
    expect(deleteResponse.statusCode, 200);
    final body = jsonDecode(deleteResponse.body) as Map<String, dynamic>;
    expect(body['success'], true);
  });

  test('POST /api/menu with negative price returns 400 (CHECK constraint)',
      () async {
    final response = await http.post(
      Uri.parse(menuUrl),
      headers: {'Content-Type': 'application/json'},
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
    final response = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tableNumber': 'T-5',
        'customerName': 'John Doe',
        'notes': 'Window seat',
        'items': [
          {
            'menuItemId': 1,
            'name': 'Masala Chai',
            'price': 2.50,
            'quantity': 2,
            'notes': 'extra hot',
          },
          {
            'menuItemId': 2,
            'name': 'Veg Sandwich',
            'price': 3.00,
            'quantity': 1,
          },
        ],
      }),
    );
    expect(response.statusCode, 201);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['tableNumber'], 'T-5');
    expect(body['status'], AppConstants.statusPending);
    expect(body['total'], 8.0); // 2*2.50 + 1*3.00
    expect(body['id'], isNotNull);
    final items = body['items'] as List<dynamic>;
    expect(items.length, 2);
    expect((items[0] as Map<String, dynamic>)['name'], 'Masala Chai');
    expect((items[0] as Map<String, dynamic>)['menuItemId'], 1);
  });

  test('GET /api/orders returns created orders with items', () async {
    await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tableNumber': 'T-10',
        'items': [
          {'name': 'Green Tea', 'price': 2.00, 'quantity': 3},
        ],
      }),
    );

    final response = await http.get(Uri.parse(ordersUrl));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List<dynamic>;
    expect(body, isNotEmpty);
    final lastOrder = body.last as Map<String, dynamic>;
    expect(lastOrder['items'], isA<List>());
    expect((lastOrder['items'] as List).length, greaterThanOrEqualTo(1));
  });

  test('GET /api/orders?status=pending filters by status', () async {
    final response = await http.get(
        Uri.parse('$ordersUrl?status=${AppConstants.statusPending}'));
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as List<dynamic>;
    for (final order in body) {
      expect((order as Map<String, dynamic>)['status'],
          AppConstants.statusPending);
    }
  });

  test('PATCH /api/orders/:id advances status pending -> preparing -> ready',
      () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tableNumber': 'T-20',
        'items': [
          {'name': 'Coffee', 'price': 2.50, 'quantity': 1},
        ],
      }),
    );
    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final id = created['id'] as int;

    var patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': AppConstants.statusPreparing}),
    );
    expect(patchResponse.statusCode, 200);
    expect(
        (jsonDecode(patchResponse.body) as Map<String, dynamic>)['status'],
        AppConstants.statusPreparing);

    patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': AppConstants.statusReady}),
    );
    expect(patchResponse.statusCode, 200);
    expect(
        (jsonDecode(patchResponse.body) as Map<String, dynamic>)['status'],
        AppConstants.statusReady);
  });

  test('PATCH /api/orders/:id with invalid status returns 400', () async {
    final createResponse = await http.post(
      Uri.parse(ordersUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tableNumber': 'T-40',
        'items': [
          {'name': 'Water', 'price': 1.00, 'quantity': 1},
        ],
      }),
    );
    final created = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final id = created['id'] as int;

    final patchResponse = await http.patch(
      Uri.parse('$ordersUrl/$id'),
      headers: {'Content-Type': 'application/json'},
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'waiter', 'password': 'waiter123'}),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
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
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'waiter', 'password': 'wrong'}),
    );
    expect(response.statusCode, 401);
  });

  test('POST /api/auth/login with unknown user returns 401', () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'nobody', 'password': 'x'}),
    );
    expect(response.statusCode, 401);
  });

  test('POST /api/auth/login with admin credentials returns admin role',
      () async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': 'admin', 'password': 'admin123'}),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
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
  // LAN IP test (192.168.50.222)
  // -------------------------------------------------------------------------

  test('server reachable over LAN IP 192.168.50.222', () async {
    const lanIp = '192.168.50.222';
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
          jsonDecode(healthResponse.body) as Map<String, dynamic>;
      expect(healthBody['status'], 'ok');

      // Fetch menu over the LAN IP.
      final menuResponse = await http.get(
        Uri.parse(
            'http://$lanIp:$lanPort${AppConstants.apiPrefix}${AppConstants.menuEndpoint}'),
      );
      expect(menuResponse.statusCode, 200);
      final menuBody = jsonDecode(menuResponse.body) as List<dynamic>;
      expect(menuBody.length, greaterThanOrEqualTo(4));

      // Submit an order over the LAN IP.
      final orderResponse = await http.post(
        Uri.parse(
            'http://$lanIp:$lanPort${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tableNumber': 'LAN-1',
          'items': [
            {'name': 'Chai', 'price': 2.00, 'quantity': 2},
          ],
        }),
      );
      expect(orderResponse.statusCode, 201);
      final orderBody =
          jsonDecode(orderResponse.body) as Map<String, dynamic>;
      expect(orderBody['tableNumber'], 'LAN-1');
      expect(orderBody['total'], 4.0);
    } finally {
      await lanServer.stop();
    }
  });
}
