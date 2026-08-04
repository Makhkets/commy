/// Reads loosely typed maps the way subscription documents actually arrive.
///
/// Clash writes `client-fingerprint`, sing-box writes `client_fingerprint`,
/// v2rayN writes `clientFingerprint`, and a hand-edited file writes whichever
/// the author remembered. Matching on a normalised key — lower-cased with
/// separators removed — absorbs all of it, and lets a caller list the genuine
/// synonyms (`servername`, `sni`, `peer`) without also listing every spelling
/// of each one.
///
/// Nothing here throws. A document from the internet gets read defensively or
/// it gets to decide what the app does (docs/06-data-model.md, rule 3).
abstract final class MapRead {
  /// The key form everything is compared in.
  static String normalise(String key) =>
      key.toLowerCase().replaceAll(RegExp('[-_ ]'), '');

  /// The raw value stored under any of [keys], or `null`.
  static Object? value(Map<String, Object?> source, List<String> keys) {
    for (final wanted in keys) {
      final target = normalise(wanted);
      for (final entry in source.entries) {
        if (normalise(entry.key) == target && entry.value != null) {
          return entry.value;
        }
      }
    }
    return null;
  }

  /// The value under any of [keys] as trimmed text, or `null` when empty.
  ///
  /// Numbers and booleans are stringified: YAML and JSON both turn `443` into
  /// an int, and a caller asking for a port as text should not have to care.
  static String? text(Map<String, Object?> source, List<String> keys) {
    final found = value(source, keys);
    if (found == null || found is Map || found is List) {
      return null;
    }
    final result = '$found'.trim();
    return result.isEmpty ? null : result;
  }

  /// The value under any of [keys] as an integer, or `null`.
  static int? integer(Map<String, Object?> source, List<String> keys) {
    final found = value(source, keys);
    if (found is int) {
      return found;
    }
    if (found is double && found == found.roundToDouble()) {
      return found.toInt();
    }
    final text = found == null ? null : '$found'.trim();
    return text == null ? null : int.tryParse(text);
  }

  /// The value under any of [keys] as a flag, or `null`.
  static bool? boolean(Map<String, Object?> source, List<String> keys) {
    final found = value(source, keys);
    if (found is bool) {
      return found;
    }
    final text = found == null ? null : '$found'.trim().toLowerCase();
    if (text == null || text.isEmpty) {
      return null;
    }
    if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
      return true;
    }
    if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
      return false;
    }
    return null;
  }

  /// The value under any of [keys] as a list of strings.
  ///
  /// Accepts a real list, a comma separated string, or a single scalar.
  static List<String> stringList(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    final found = value(source, keys);
    if (found == null) {
      return const <String>[];
    }
    if (found is List) {
      return <String>[
        for (final item in found)
          if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
      ];
    }
    if (found is Map) {
      return const <String>[];
    }
    return <String>[
      for (final part in '$found'.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  /// The value under any of [keys] as a nested map, or `null`.
  static Map<String, Object?>? object(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    final found = value(source, keys);
    if (found is Map<String, Object?>) {
      return found;
    }
    if (found is Map) {
      return <String, Object?>{
        for (final entry in found.entries) '${entry.key}': entry.value,
      };
    }
    return null;
  }

  /// The value under any of [keys] as a list of maps.
  static List<Map<String, Object?>> objectList(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    final found = value(source, keys);
    if (found is! List) {
      return const <Map<String, Object?>>[];
    }
    final result = <Map<String, Object?>>[];
    for (final item in found) {
      if (item is Map<String, Object?>) {
        result.add(item);
      } else if (item is Map) {
        result.add(<String, Object?>{
          for (final entry in item.entries) '${entry.key}': entry.value,
        });
      }
    }
    return result;
  }
}
