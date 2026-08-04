import 'package:commy_data/src/secure/secret_vault.dart';
import 'package:sqlite3/sqlite3.dart';

/// Whether the database file on disk is encrypted, and why not when it is not.
///
/// The distinction is a product-visible one: the settings screen has to be able
/// to tell the user which of these applies. Silently shipping
/// [DatabaseEncryptionStatus.unavailable] while claiming encryption would be
/// exactly the "молчаливая деградация" docs/09-security-privacy.md calls a bug.
enum DatabaseEncryptionStatus {
  /// The file is encrypted with a key held in the platform keystore.
  encrypted,

  /// This build's SQLite has no cipher, so the file holds plain metadata.
  ///
  /// Not a downgrade of rule R2: every credential still lives in the keystore
  /// and never reaches the file. What stays readable is metadata — node names,
  /// countries, hosts, timestamps — which
  /// docs/adr/0007-database-encryption.md accepts explicitly.
  unavailable,

  /// A key was wanted but the keystore would not produce one.
  ///
  /// The database is open and plain, and the app is in a degraded state it must
  /// surface rather than hide.
  keyUnavailable,
}

/// The key and the cipher probe for the database file.
///
/// Two independent questions live here:
///
/// 1. *Can this build encrypt at all?* [probeCipherSupport] asks the linked
///    SQLite whether it answers `PRAGMA cipher_version`. Plain SQLite returns
///    no rows for an unknown pragma, SQLCipher and SQLite3MultipleCiphers
///    return their version.
/// 2. *Do we have a key?* [obtainKey] pulls 32 CSPRNG bytes out of
///    `SecretVault`, generating them once on first run.
///
/// If both answer yes the file is opened with `PRAGMA key`. If either says no
/// the file is opened plain and the caller gets a status it is expected to show
/// — see `openCommyDatabase`.
class DatabaseEncryption {
  /// Creates the helper.
  DatabaseEncryption({required SecretVault vault}) : _vault = vault;

  /// Pragma used to ask whether the loaded SQLite carries a cipher.
  static const String cipherProbePragma = 'PRAGMA cipher_version;';

  final SecretVault _vault;

  /// Whether the SQLite this process loaded can encrypt a database file.
  ///
  /// Runs on the calling isolate against a throwaway in-memory handle, so the
  /// answer is known *before* the real file is opened in a background isolate.
  /// Any exception counts as "no": an unknown pragma must never be the reason
  /// the app fails to start.
  static bool probeCipherSupport() {
    Database? probe;
    try {
      probe = sqlite3.openInMemory();
      final rows = probe.select(cipherProbePragma);
      if (rows.isEmpty) {
        return false;
      }
      final value = rows.first.values.isEmpty ? null : rows.first.values.first;
      return value != null && '$value'.isNotEmpty;
    } on Object catch (_) {
      return false;
    } finally {
      // sqlite3's Database.close() is synchronous — this probe is deliberately
      // sync so the answer is known before any isolate is spawned.
      probe?.close();
    }
  }

  /// The hex database key, or `null` when the keystore could not give one.
  Future<String?> obtainKey() async {
    final result = await _vault.ensureDatabaseKey();
    return result.valueOrNull;
  }

  /// Decides how the file will be opened, and with which key.
  ///
  /// Returns the key only when it will actually be applied, so a caller cannot
  /// accidentally log a key it is not even using.
  Future<DatabaseEncryptionPlan> plan() async {
    if (!probeCipherSupport()) {
      return const DatabaseEncryptionPlan(
        status: DatabaseEncryptionStatus.unavailable,
      );
    }
    final key = await obtainKey();
    if (key == null || key.isEmpty) {
      return const DatabaseEncryptionPlan(
        status: DatabaseEncryptionStatus.keyUnavailable,
      );
    }
    return DatabaseEncryptionPlan(
      status: DatabaseEncryptionStatus.encrypted,
      keyHex: key,
    );
  }

  /// Applies [keyHex] to an already open [database].
  ///
  /// Kept separate from `plan` because it has to run inside the connection
  /// setup callback, which drift may execute on another isolate. `PRAGMA key`
  /// must be the first statement on the connection — anything before it reads
  /// the file header and fails.
  static void applyKey(Database database, String keyHex) {
    database.execute("PRAGMA key = \"x'$keyHex'\";");
  }
}

/// The outcome of `DatabaseEncryption.plan`.
class DatabaseEncryptionPlan {
  /// Creates a plan.
  const DatabaseEncryptionPlan({required this.status, this.keyHex});

  /// What will happen when the file is opened.
  final DatabaseEncryptionStatus status;

  /// The hex key, present only when [status] is
  /// [DatabaseEncryptionStatus.encrypted].
  final String? keyHex;

  /// Whether the file will be encrypted.
  bool get isEncrypted => status == DatabaseEncryptionStatus.encrypted;

  /// Never prints [keyHex].
  @override
  String toString() => 'DatabaseEncryptionPlan(${status.name})';
}
