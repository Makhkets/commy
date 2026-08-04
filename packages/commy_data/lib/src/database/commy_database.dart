import 'package:commy_data/src/database/tables/import_failure_rows.dart';
import 'package:commy_data/src/database/tables/node_group_rows.dart';
import 'package:commy_data/src/database/tables/node_rows.dart';
import 'package:commy_data/src/database/tables/routing_rule_rows.dart';
import 'package:commy_data/src/database/tables/setting_rows.dart';
import 'package:commy_data/src/database/tables/subscription_rows.dart';
import 'package:commy_data/src/database/tables/traffic_daily_rows.dart';
import 'package:drift/drift.dart';

part 'commy_database.g.dart';

/// The plain half of Commy's storage.
///
/// "Plain" is the operative word: this file holds metadata only. Credentials,
/// subscription URLs and the generated core configuration live in the platform
/// keystore behind `SecretVault` (rule R2, docs/adr/0007-database-encryption.md
/// — full-file encryption was dropped in 1.0 because both SQLCipher shims went
/// end of life, and Keystore-backed storage of the actual secrets is strictly
/// stronger than a database key kept next to the database).
///
/// `DatabaseEncryption` still carries the encrypted-file code path and reports
/// whether it could be used, so a build with a cipher-capable SQLite gets
/// encryption at rest for the metadata too.
@DriftDatabase(
  tables: <Type>[
    SubscriptionRows,
    NodeGroupRows,
    NodeRows,
    RoutingRuleRows,
    SettingRows,
    TrafficDailyRows,
    ImportFailureRows,
  ],
)
class CommyDatabase extends _$CommyDatabase {
  /// Opens the database on the given executor.
  ///
  /// The parameter is called `e` because drift's generated superclass calls it
  /// that, and a super-parameter has to match the name it forwards to.
  CommyDatabase(super.e);

  /// The schema this build writes.
  ///
  /// Bump it in the same commit that adds the matching `if (from < n)` block in
  /// [migration] and the matching test. A VPN client that loses every profile
  /// on update has lost the user (docs/06-data-model.md, "Миграции").
  static const int currentSchemaVersion = 1;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
        },
        onUpgrade: (migrator, from, to) async {
          // Forward only, one guarded block per version, never a `default`.
          // Each block must be idempotent from the version below it, because a
          // user can skip releases: 1 → 4 runs three blocks in a row.
          if (from < 1) {
            await migrator.createAll();
          }
          // Version 2 goes here:
          // if (from < 2) {
          //   await migrator.addColumn(nodeRows, nodeRows.someNewColumn);
          // }
        },
        beforeOpen: (details) async {
          // The node table cascades off subscriptions and groups, and SQLite
          // ignores foreign keys unless asked, per connection.
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated || details.hadUpgrade) {
            await customStatement('PRAGMA foreign_key_check');
          }
        },
      );

  /// Deletes every row in every table, leaving the schema alone.
  ///
  /// The database half of "erase all data"; the caller wipes `SecretVault`
  /// in the same breath, or the keystore keeps orphaned credentials.
  Future<void> clearAll() => transaction(() async {
        for (final table in allTables) {
          await delete(table).go();
        }
      });
}
