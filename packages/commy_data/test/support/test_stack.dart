import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/native.dart';

/// A whole storage stack, in memory, for one test.
///
/// The database is a fresh `NativeDatabase.memory()` — the migration runs for
/// real, so every test also exercises `onCreate`. The keystore is
/// `InMemorySecureStore`, which is what makes the rule R2 assertions possible:
/// a test can look at both halves and check that each secret is in the right
/// one.
///
/// Note for whoever runs this on a bare machine: `NativeDatabase` needs a
/// SQLite library on the host. `package:sqlite3` 3.x builds one through its
/// build hooks; if `flutter test` on this platform cannot, it shows up here
/// first, as a failure to open the database rather than a failed assertion.
class TestStack {
  /// Creates a stack.
  TestStack({
    required this.database,
    required this.store,
    required this.vault,
  });

  /// Builds a fresh in-memory stack.
  factory TestStack.create({InMemorySecureStore? store}) {
    final secureStore = store ?? InMemorySecureStore();
    return TestStack(
      database: CommyDatabase(NativeDatabase.memory()),
      store: secureStore,
      vault: SecretVault(store: secureStore),
    );
  }

  /// The in-memory database.
  final CommyDatabase database;

  /// The in-memory keystore, inspectable through `snapshot`.
  final InMemorySecureStore store;

  /// The vault wrapping [store].
  final SecretVault vault;

  /// Identifier source for the stores that mint their own ids.
  final IdGenerator ids = RandomIdGenerator();

  /// A node repository over this stack.
  DriftNodeRepository get nodes =>
      DriftNodeRepository(database: database, secrets: vault);

  /// A subscription repository over this stack.
  DriftSubscriptionRepository get subscriptions =>
      DriftSubscriptionRepository(database: database, secrets: vault);

  /// A settings repository over this stack.
  DriftSettingsRepository get settings =>
      DriftSettingsRepository(database: database);

  /// A routing repository over this stack.
  DriftRoutingRepository get routing =>
      DriftRoutingRepository(database: database);

  /// A traffic history store over this stack.
  DriftTrafficHistoryStore get traffic =>
      DriftTrafficHistoryStore(database: database);

  /// An import failure store over this stack.
  DriftImportFailureStore get importFailures =>
      DriftImportFailureStore(database: database, ids: ids);

  /// Every value in every column of every table, as text.
  ///
  /// The R2 guard test scans this for credentials. It goes through
  /// `customSelect` rather than the typed API on purpose: the question is what
  /// the *file* holds, not what the mappers say it holds.
  Future<List<String>> dumpAllValues() async {
    final values = <String>[];
    for (final table in database.allTables) {
      final rows = await database
          .customSelect('SELECT * FROM ${table.actualTableName}')
          .get();
      for (final row in rows) {
        for (final value in row.data.values) {
          if (value != null) {
            values.add('$value');
          }
        }
      }
    }
    return values;
  }

  /// Closes the database.
  Future<void> dispose() => database.close();
}
