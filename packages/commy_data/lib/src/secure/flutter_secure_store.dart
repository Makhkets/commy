import 'package:commy_data/src/secure/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The real secure store, on top of `flutter_secure_storage`.
///
/// No platform option objects are passed. On Android there is nothing left to
/// pass: version 11 removed the EncryptedSharedPreferences backend and the
/// legacy ciphers along with it, so what used to be worth asking for is now
/// the only thing on offer — AES-GCM over a key wrapped with
/// RSA-OAEP-SHA-256 in the Android keystore. Naming the defaults would buy
/// nothing and go stale on the next major.
///
/// iOS still has a choice worth making, and it is the composition root's to
/// make: the default accessibility is `unlocked`, which a tunnel that comes up
/// after a reboot cannot read until someone has unlocked the device once. The
/// store should be constructed with
/// `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`,
/// which reads in that window and also keeps the items out of a backup
/// restored onto another device. It does not change the data format.
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
