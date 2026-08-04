import 'package:commy_data/src/secure/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The real secure store, on top of `flutter_secure_storage`.
///
/// No platform option objects are passed on purpose. The dependency range in
/// `pubspec.yaml` spans two major versions whose `AndroidOptions` and
/// `IOSOptions` fields differ, and picking the wrong field name is a compile
/// error on one of them. Once `.fvmrc` pins a Flutter version and the range
/// narrows, the composition root should construct this with explicit
/// `AndroidOptions(encryptedSharedPreferences: true)` and an iOS accessibility
/// of "first unlock, this device only" — both are strictly tighter than the
/// defaults, and neither changes the data format.
class FlutterSecureStore implements SecureStore {
  /// Creates the store.
  ///
  /// [storage] is injectable so a test can hand in a fake without dragging the
  /// platform channel in.
  FlutterSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();

  @override
  Future<bool> contains(String key) => _storage.containsKey(key: key);
}
