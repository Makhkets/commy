import 'dart:convert';

import 'package:commy_core/src/wire/wire_format_exception.dart';
import 'package:commy_domain/commy_domain.dart';

/// Lenient readers for the JSON that arrives from the core.
///
/// Lenient on purpose, and only here: the input is a foreign process that may
/// be a version ahead of us. Missing optional fields fall back, unknown fields
/// are ignored, a number that arrived as a string still parses. What is *not*
/// tolerated is a payload that is not an object at all — that is a protocol
/// break and it throws [WireFormatException].
abstract final class WireJson {
  /// Decodes [raw] into a JSON object.
  static JsonMap object(Object? raw, String what) {
    final decoded = _decode(raw, what);
    final map = asMap(decoded);
    if (map == null) {
      throw WireFormatException(what, 'expected a JSON object');
    }
    return map;
  }

  /// Decodes [raw] into a list of JSON objects.
  ///
  /// Accepts both a bare array and a single object, because the log channel
  /// sends one line as an object and a batch as an array.
  static List<JsonMap> objectList(Object? raw, String what) {
    final decoded = _decode(raw, what);
    if (decoded is List<Object?>) {
      final items = <JsonMap>[];
      for (final item in decoded) {
        final map = asMap(item);
        if (map != null) {
          items.add(map);
        }
      }
      return items;
    }
    final single = asMap(decoded);
    if (single == null) {
      throw WireFormatException(what, 'expected a JSON object or array');
    }
    return <JsonMap>[single];
  }

  /// Re-keys any map into a [JsonMap], or returns `null` when it is not one.
  static JsonMap? asMap(Object? value) {
    if (value is JsonMap) {
      return value;
    }
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
    }
    return null;
  }

  /// Reads an integer that may have arrived as a number or as a string.
  static int? integerOrNull(JsonMap json, String key) {
    final raw = json[key];
    if (raw is num) {
      return raw.toInt();
    }
    if (raw is String) {
      return int.tryParse(raw) ?? double.tryParse(raw)?.toInt();
    }
    return null;
  }

  /// Reads an integer, falling back to [orElse].
  static int integerOr(JsonMap json, String key, {required int orElse}) =>
      integerOrNull(json, key) ?? orElse;

  /// Reads a string, falling back to [orElse].
  static String stringOr(JsonMap json, String key, {required String orElse}) {
    final raw = json[key];
    if (raw == null) {
      return orElse;
    }
    return raw is String ? raw : '$raw';
  }

  /// Reads an optional string, treating an empty one as absent.
  static String? stringOrNull(JsonMap json, String key) {
    final raw = json[key];
    if (raw == null) {
      return null;
    }
    final text = raw is String ? raw : '$raw';
    return text.isEmpty ? null : text;
  }

  /// Reads a timestamp stored as epoch milliseconds.
  ///
  /// Returns `null` when the field is absent or not a number. Values are read
  /// as UTC and converted to local time, which is what the UI renders.
  static DateTime? epochMillisOrNull(JsonMap json, String key) {
    final millis = integerOrNull(json, key);
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }

  /// Reads a timestamp, falling back to [orElse].
  static DateTime epochMillisOr(
    JsonMap json,
    String key, {
    required DateTime orElse,
  }) =>
      epochMillisOrNull(json, key) ?? orElse;

  /// Reads a list of strings, ignoring anything that is not one.
  static List<String> stringList(JsonMap json, String key) {
    final raw = json[key];
    if (raw is! List<Object?>) {
      return const <String>[];
    }
    return <String>[
      for (final item in raw)
        if (item != null) '$item',
    ];
  }

  static Object? _decode(Object? raw, String what) {
    if (raw is String) {
      try {
        return jsonDecode(raw);
      } on FormatException catch (error) {
        throw WireFormatException(what, error);
      }
    }
    return raw;
  }
}
