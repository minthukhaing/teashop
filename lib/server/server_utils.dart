library teashop_pos.server.server_utils;

import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../core/utils/myanmar_text.dart';

/// Reads the JSON object body from a [Request]. Returns `{}` for an empty body.
///
/// The body is decoded as UTF-8 and every string is normalized to NFC so
/// Burmese text arriving in decomposed form is canonical before persistence.
Future<Map<String, dynamic>> readJsonBody(Request request) async {
  final body = await request.readAsString(utf8);
  if (body.isEmpty) return <String, dynamic>{};
  return MyanmarText.normalizeJson(jsonDecode(body)) as Map<String, dynamic>;
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
