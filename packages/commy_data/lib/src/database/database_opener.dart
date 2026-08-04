import 'dart:io';

import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/database/database_encryption.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// An open database plus the truth about how it is protected.
///
/// The status travels with the handle so the composition root cannot forget to
/// look at it: "the file turned out not to be encrypted" is something the user
/// is entitled to know, and a value returned by the opener is harder to ignore
/// than a log line nobody reads.
class OpenedDatabase {
  /// Creates the pair.
  const OpenedDatabase({required this.database, required this.encryption});

  /// The database, migrated and ready.
  final CommyDatabase database;

  /// Whether the file on disk is encrypted, and why not when it is not.
  final DatabaseEncryptionStatus encryption;

  /// Whether the app should show the "reduced protection" indicator.
  bool get isDegraded => encryption != DatabaseEncryptionStatus.encrypted;

  @override
  String toString() => 'OpenedDatabase(${encryption.name})';
}

/// Name of the database file inside the application support directory.
const String commyDatabaseFileName = 'commy.sqlite';

/// Opens the real, on-disk database.
///
/// The file lives in the application support directory — not in documents,
/// which on iOS is user-visible and backed up to iCloud, and we do not put a
/// list of someone's proxy servers into anybody's cloud
/// (docs/00-vision.md, "явные non-goals").
///
/// [encryption] decides whether a `PRAGMA key` is applied. When it cannot be,
/// the database still opens and the returned [OpenedDatabase] says so.
Future<OpenedDatabase> openCommyDatabase({
  required DatabaseEncryption encryption,
  String fileName = commyDatabaseFileName,
  Directory? directory,
}) async {
  final target = directory ?? await getApplicationSupportDirectory();
  await target.create(recursive: true);
  final file = File(p.join(target.path, fileName));

  final plan = await encryption.plan();
  final keyHex = plan.keyHex;

  final executor = NativeDatabase.createInBackground(
    file,
    setup: (rawDatabase) {
      if (keyHex != null) {
        // Must be the first statement on the connection.
        DatabaseEncryption.applyKey(rawDatabase, keyHex);
      }
      // Fewer fsyncs, still crash-safe, and it is what every mobile SQLite
      // ships with.
      rawDatabase
        ..execute('PRAGMA journal_mode = WAL;')
        ..execute('PRAGMA busy_timeout = 5000;');
    },
  );

  return OpenedDatabase(
    database: CommyDatabase(executor),
    encryption: plan.status,
  );
}

/// Opens a throwaway in-memory database.
///
/// Used by tests and by the "what would a fresh install look like" paths. Never
/// encrypted: there is no file to protect.
CommyDatabase openInMemoryCommyDatabase() =>
    CommyDatabase(NativeDatabase.memory());

/// Opens an in-memory database on an explicit sqlite3 handle.
///
/// The R2 guard test needs the raw handle afterwards to dump every table byte
/// for byte, which `NativeDatabase.memory()` does not hand back.
QueryExecutor inMemoryExecutorOn(Database raw) =>
    NativeDatabase.opened(raw, closeUnderlyingOnClose: false);
