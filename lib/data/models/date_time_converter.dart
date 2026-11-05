library teashop_pos.data.models.date_time_converter;

import 'package:json_annotation/json_annotation.dart';

/// Converts between Dart [DateTime] and ISO-8601 strings for JSON/SQLite.
///
/// Storing dates as ISO-8601 strings keeps the local database human-readable
/// and portable across the Admin Host and clients.
class IsoDateTimeConverter implements JsonConverter<DateTime?, String?> {
  const IsoDateTimeConverter();

  @override
  DateTime? fromJson(String? json) {
    if (json == null || json.isEmpty) return null;
    return DateTime.tryParse(json);
  }

  @override
  String? toJson(DateTime? date) => date?.toIso8601String();
}
