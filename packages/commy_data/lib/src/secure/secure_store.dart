/// The key-value store backed by the platform keystore.
///
/// Rule R2 lives here: everything whose leak would give someone access to the
/// user's own servers goes through this interface and never into a database
/// column. Backends are Keychain (Apple), Keystore or EncryptedSharedPrefs
/// (Android), DPAPI (Windows) and libsecret (Linux)
/// — see docs/adr/0007-database-encryption.md.
///
/// Methods throw. Callers wrap them; the repositories do it through
/// `StorageGuard` and hand back a `StorageFailure`.
abstract interface class SecureStore {
  /// The value stored under [key], or `null`.
  Future<String?> read(String key);

  /// Every entry this app owns. Used to hydrate a whole list in one call.
  Future<Map<String, String>> readAll();

  /// Stores [value] under [key], replacing whatever was there.
  Future<void> write(String key, String value);

  /// Removes [key]. Removing something absent is not an error.
  Future<void> delete(String key);

  /// Removes every entry. Only ever called by "erase all data".
  Future<void> deleteAll();

  /// Whether [key] currently holds a value.
  Future<bool> contains(String key);
}
