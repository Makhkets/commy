/// Deep comparison helpers for hand-written `==` and `hashCode` overrides.
///
/// `package:collection` would do this, but commy_domain carries no
/// dependencies at all — see docs/adr/0006-codegen-and-native-layout.md.
abstract final class Structural {
  /// Whether two lists hold equal elements in the same order.
  static bool listEquals<T>(List<T> a, List<T> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  /// Whether two maps hold the same keys mapped to equal values.
  static bool mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  /// Order-sensitive hash of a list.
  static int listHash<T>(List<T> items) => Object.hashAll(items);

  /// Order-independent hash of a map.
  static int mapHash<K, V>(Map<K, V> map) {
    var hash = 0;
    for (final entry in map.entries) {
      hash ^= Object.hash(entry.key, entry.value);
    }
    return hash;
  }
}
