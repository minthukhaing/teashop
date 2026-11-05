library teashop_pos.server.app_server;

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../core/constants/app_constants.dart';
import '../data/database/app_database.dart';
import 'handlers/menu_handler.dart';
import 'handlers/order_handler.dart';
import 'handlers/auth_handler.dart';
import 'server_utils.dart';

/// The local HTTP server that runs on the Admin Host.
///
/// Binds to every IPv4 interface on port 8080 so Waiter and Kitchen clients
/// on the same Wi-Fi LAN can reach it without internet access.
class AppServer {
  AppServer.withDb(AppDatabase database)
      : _menu = MenuHandler(database),
        _orders = OrderHandler(database),
        _auth = AuthHandler(database);

  final MenuHandler _menu;
  final OrderHandler _orders;
  final AuthHandler _auth;

  HttpServer? _httpServer;
  final Router _router = Router();

  /// The composed HTTP handler (CORS + routing + logging).
  Handler get handler {
    return _cors(_logRequests(_router));
  }

  Handler _cors(Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response(
          200,
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type',
          },
        );
      }
      final response = await handler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
      });
    };
  }

  /// Starts listening on [address]:[port].
  /// [address] defaults to [AppConstants.serverBindAddress] (any IPv4 interface).
  Future<void> start({
    int port = AppConstants.serverPort,
    InternetAddress? address,
  }) async {
    address ??= AppConstants.serverBindAddress;
    _router.get(AppConstants.healthEndpoint, _handleHealth);
    _router.get(
      '${AppConstants.apiPrefix}${AppConstants.menuEndpoint}',
      _menu.getMenu,
    );
    _router.post(
      '${AppConstants.apiPrefix}${AppConstants.menuEndpoint}',
      _menu.createMenu,
    );
    _router.put(
      '${AppConstants.apiPrefix}${AppConstants.menuEndpoint}/<id>',
      _menu.updateMenu,
    );
    _router.delete(
      '${AppConstants.apiPrefix}${AppConstants.menuEndpoint}/<id>',
      _menu.deleteMenu,
    );
    _router.get(
      '${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}',
      _orders.getOrders,
    );
    _router.post(
      '${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}',
      _orders.createOrder,
    );
    _router.patch(
      '${AppConstants.apiPrefix}${AppConstants.ordersEndpoint}/<id>',
      _orders.updateOrderStatus,
    );
    _router.post(
      '${AppConstants.apiPrefix}${AppConstants.authEndpoint}/login',
      _auth.login,
    );

    _httpServer = await HttpServer.bind(address, port);
    _httpServer!.listen(_onHttpRequest);
    print('Teashop POS Admin server listening on http://$address:$port');
  }

  /// Stops the server and releases the port.
  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  void _onHttpRequest(HttpRequest httpRequest) async {
    try {
      // Build a shelf Request from the raw HttpRequest.
      final requestHeaders = <String, String>{};
      httpRequest.headers.forEach((name, values) {
        requestHeaders[name] = values.first;
      });
      // shelf's Request requires an absolute URI, but HttpRequest.uri is
      // typically just the path + query (e.g. "/api/menu?available=true").
      // Use the Host header (or localhost fallback) to build a full URL.
      final requestUri = httpRequest.uri;
      final host = requestHeaders['host'] ?? 'localhost';
      final absoluteUri = requestUri.isAbsolute
          ? requestUri
          : Uri.parse('http://$host$requestUri');
      final shelfRequest = Request(
        httpRequest.method,
        absoluteUri,
        headers: requestHeaders,
        body: httpRequest,
        encoding: utf8,
      );
      final shelfResponse = await handler(shelfRequest);
      final httpResponse = httpRequest.response
        ..statusCode = shelfResponse.statusCode
        ..headers.contentType = ContentType('application', 'json',
            charset: 'utf-8');
      shelfResponse.headers.forEach((k, v) {
        httpResponse.headers.set(k, v);
      });
      final bodyString = await shelfResponse.readAsString();
      httpResponse.add(utf8.encode(bodyString));
      await httpResponse.close();
    } catch (e, stack) {
      print('Request error: $e\n$stack');
      try {
        await httpRequest.response.close();
      } catch (_) {}
    }
  }

  Future<Response> _handleHealth(Request request) async {
    return jsonResponse({
      'status': 'ok',
      'time': DateTime.now().toIso8601String(),
      'server': 'teashop-pos-admin',
    });
  }

  Handler _logRequests(Handler handler) {
    return (Request request) async {
      final started = DateTime.now();
      final response = await handler(request);
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      print('${request.method} ${request.url.path} -> ${response.statusCode} '
          '(${elapsed}ms)');
      return response;
    };
  }
}
