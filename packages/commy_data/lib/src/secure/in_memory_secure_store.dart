import 'package:commy_data/src/secure/secure_store.dart';

/// A secure store that keeps everything in a map.
///
/// For tests only. It ships in `lib/` rather than in `test/` because the app
/// and the other packages need it for their own tests, and because a widget
/// test that touched the real platform channel would hang.
///
/// [failOnWrite] and [failOnRead] make the "Linux without a keyring" path
/// testable: the repositories have to survive a store that refuses to work
/// (docs/09-security-privacy.md, "Известная слабость").
class InMemorySecureStore implements SecureStore {
  /// Creates an empty store.
  InMemorySecureStore({
    Map<String, String>? initial,
    this.failOnWrite = false,
    this.failOnRead = false,
  }) : _values = <String, String>{...?initial};

  /// Whether every write throws, as an unavailable keyring would.
  final bool failOnWrite;

  /// Whether every read throws.
  final bool failOnRead;

  final Map<String, String> _values;

  /// A snapshot of the contents, for assertions.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_values);

  @override
  Future<String?> read(String key) async {
    _guardRead();
    return _values[key];
  }

  @override
  Future<Map<String, String>> readAll() async {
    _guardRead();
    return Map<String, String>.from(_values);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failOnWrite) {
      throw StateError('secure storage unavailable');
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failOnWrite) {
      throw StateError('secure storage unavailable');
    }
    _values.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    if (failOnWrite) {
      throw StateError('secure storage unavailable');
    }
    _values.clear();
  }

  @override
  Future<bool> contains(String key) async {
    _guardRead();
    return _values.containsKey(key);
  }

  void _guardRead() {
    if (failOnRead) {
      throw StateError('secure storage unavailable');
    }
  }
}
