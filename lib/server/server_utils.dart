library teashop_pos.server.server_utils;

import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Reads the JSON object body from a [Request]. Returns `{}` for an empty body.
Future<Map<String, dynamic>> readJsonBody(Request request) async {
  final body = await request.readAsString();
  if (body.isEmpty) return <String, dynamic>{};
  return jsonDecode(body) as Map<String, dynamic>;
}

/// Builds a JSON [Response].
Response jsonResponse(Object body, {int statusCode = 200}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

/// Builds a JSON error [Response].
Response errorResponse(String message, {int statusCode = 400}) {
  return jsonResponse({'error': message}, statusCode: statusCode);
}
