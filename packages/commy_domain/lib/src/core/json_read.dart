import 'package:commy_domain/src/core/json_map.dart';

/// Typed accessors for hand-written `fromJson` factories.
///
/// These throw on malformed input on purpose: decoding happens inside the data
/// layer, which already wraps every call in a try/catch and turns the failure
/// into a `StorageFailure`. Keeping the accessors strict means a corrupted row
/// is loud instead of silently becoming an empty node.
abstract final class JsonRead {
  /// Reads a required [String].
  static String string(JsonMap json, String key) => json[key]! as String;

  /// Reads an optional [String].
  static String? stringOrNull(JsonMap json, String key) => json[key] as String?;

  /// Reads a required [int].
  static int integer(JsonMap json, String key) => (json[key]! as num).toInt();

  /// Reads an optional [int].
  static int? integerOrNull(JsonMap json, String key) =>
      (json[key] as num?)?.toInt();

  /// Reads a [bool], falling back to [orElse] when the key is absent.
  static bool boolean(JsonMap json, String key, {required bool orElse}) =>
      json[key] as bool? ?? orElse;

  /// Reads an [int], falling back to [orElse] when the key is absent.
  static int integerOr(JsonMap json, String key, {required int orElse}) =>
      (json[key] as num?)?.toInt() ?? orElse;

  /// Reads a [String], falling back to [orElse] when the key is absent.
  static String stringOr(JsonMap json, String key, {required String orElse}) =>
      json[key] as String? ?? orElse;

  /// Reads an optional ISO-8601 timestamp.
  static DateTime? dateTimeOrNull(JsonMap json, String key) {
    final raw = json[key] as String?;
    return raw == null ? null : DateTime.parse(raw);
  }

  /// Reads a required ISO-8601 timestamp.
  static DateTime dateTime(JsonMap json, String key) =>
      DateTime.parse(json[key]! as String);

  /// Reads an optional [Duration] stored as whole microseconds.
  static Duration? durationOrNull(JsonMap json, String key) {
    final raw = json[key] as num?;
    return raw == null ? null : Duration(microseconds: raw.toInt());
  }

  /// Reads an optional [Uri].
  static Uri? uriOrNull(JsonMap json, String key) {
    final raw = json[key] as String?;
    return raw == null ? null : Uri.parse(raw);
  }

  /// Reads a required [Uri].
  static Uri uri(JsonMap json, String key) => Uri.parse(json[key]! as String);

  /// Reads a nested object, returning an empty map when absent or malformed.
  static JsonMap objectOrEmpty(JsonMap json, String key) {
    final raw = json[key];
    if (raw is! Map<Object?, Object?>) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      for (final entry in raw.entries) '${entry.key}': entry.value,
    };
  }

  /// Reads a list of strings, returning an empty list when absent.
  static List<String> stringList(JsonMap json, String key) {
    final raw = json[key];
    if (raw is! List<Object?>) {
      return const <String>[];
    }
    return <String>[for (final item in raw) '$item'];
  }

  /// Reads a list of nested objects, skipping anything that is not one.
  static List<JsonMap> objectList(JsonMap json, String key) {
    final raw = json[key];
    if (raw is! List<Object?>) {
      return const <JsonMap>[];
    }
    return <JsonMap>[
      for (final item in raw)
        if (item is Map<Object?, Object?>)
          <String, Object?>{
            for (final entry in item.entries) '${entry.key}': entry.value,
          },
    ];
  }
}
