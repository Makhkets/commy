import 'package:commy_config/src/internal/percent.dart';

/// The query string of a proxy link, read the way real links need it read.
///
/// Three things a plain `Map<String, String>` gets wrong:
/// * keys repeat — `alpn=h2&alpn=http/1.1` is legal and common;
/// * keys differ in case and spelling between panels — `sni`, `SNI`, `peer`;
/// * values arrive percent-encoded, sometimes twice, sometimes not at all.
class QueryMap {
  const QueryMap._(this._entries);

  /// Parses a raw query string, without the leading `?`.
  factory QueryMap.parse(String raw) {
    final entries = <MapEntry<String, String>>[];
    for (final pair in raw.split('&')) {
      if (pair.trim().isEmpty) {
        continue;
      }
      final split = pair.indexOf('=');
      final rawKey = split < 0 ? pair : pair.substring(0, split);
      final rawValue = split < 0 ? '' : pair.substring(split + 1);
      final key = Percent.decode(rawKey).trim();
      if (key.isEmpty) {
        continue;
      }
      entries.add(MapEntry<String, String>(key, Percent.decode(rawValue)));
    }
    return QueryMap._(entries);
  }

  /// A query string with nothing in it.
  static const QueryMap empty = QueryMap._(<MapEntry<String, String>>[]);

  /// Values a panel may write instead of `true`.
  static const Set<String> truthy = <String>{'1', 'true', 'yes', 'on'};

  final List<MapEntry<String, String>> _entries;

  /// Whether the query held nothing at all.
  bool get isEmpty => _entries.isEmpty;

  /// Whether the query held anything.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Every value recorded for [key], in the order they appeared.
  List<String> all(String key) {
    final wanted = key.toLowerCase();
    return <String>[
      for (final entry in _entries)
        if (entry.key.toLowerCase() == wanted) entry.value,
    ];
  }

  /// The first non-empty value of [key], or `null`.
  String? first(String key) {
    for (final value in all(key)) {
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  /// The first non-empty value of any of [keys], tried in order.
  ///
  /// This is how the spelling differences between panels are absorbed:
  /// `firstOf(['sni', 'peer', 'servername'])`.
  String? firstOf(List<String> keys) {
    for (final key in keys) {
      final value = first(key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Reads [key] as a boolean flag, falling back to [orElse].
  bool flag(String key, {required bool orElse}) {
    final value = first(key);
    if (value == null) {
      return orElse;
    }
    return truthy.contains(value.toLowerCase());
  }

  /// Reads any of [keys] as a boolean flag, falling back to [orElse].
  bool flagOf(List<String> keys, {required bool orElse}) {
    for (final key in keys) {
      if (first(key) != null) {
        return flag(key, orElse: orElse);
      }
    }
    return orElse;
  }

  /// Reads [key] as an integer, or `null` when absent or not a number.
  int? integer(String key) {
    final value = first(key);
    return value == null ? null : int.tryParse(value);
  }

  /// Reads any of [keys] as an integer, or `null`.
  int? integerOf(List<String> keys) {
    for (final key in keys) {
      final value = integer(key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  /// Reads [key] as a comma separated list, flattening repeated keys.
  List<String> csv(String key) {
    final result = <String>[];
    for (final value in all(key)) {
      for (final part in value.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) {
          result.add(trimmed);
        }
      }
    }
    return result;
  }

  /// Reads any of [keys] as a comma separated list.
  List<String> csvOf(List<String> keys) {
    for (final key in keys) {
      final values = csv(key);
      if (values.isNotEmpty) {
        return values;
      }
    }
    return const <String>[];
  }

  /// A flat view keeping the first value of every key.
  Map<String, String> toMap() {
    final result = <String, String>{};
    for (final entry in _entries) {
      result.putIfAbsent(entry.key, () => entry.value);
    }
    return result;
  }

  @override
  String toString() => 'QueryMap(${_entries.length} entries)';
}
