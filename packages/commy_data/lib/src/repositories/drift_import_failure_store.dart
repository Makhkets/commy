import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/models/stored_import_failure.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// What an import could not understand, kept so the user can act on it.
///
/// No domain port exists for this: "partial success is success" is a UI
/// affordance rather than a use case, and the list is read by exactly one
/// screen. The table is still worth having — a user who pasted fifty links and
/// got forty nodes deserves to see the other ten and why.
///
/// **The redaction is not optional.** `ImportFailure.rawLine` is the text the
/// user pasted, so it is typically a live `vless://` link with a working uuid
/// in it. Only `ImportFailure.redactedLine` is written, and the raw line never
/// reaches the disk (rule R2 and rule R3 pulling in the same direction).
class DriftImportFailureStore {
  /// Creates the store.
  DriftImportFailureStore({
    required CommyDatabase database,
    required IdGenerator ids,
  })  : _db = database,
        _ids = ids;

  /// How many failures are kept before the oldest are dropped.
  ///
  /// A broken subscription can produce thousands; the screen shows the recent
  /// ones and nobody scrolls past a hundred.
  static const int retainedCount = 200;

  final CommyDatabase _db;
  final IdGenerator _ids;

  /// The stored failures, newest first, refreshed on every change.
  Stream<List<StoredImportFailure>> watchAll() =>
      _ordered().watch().map(_mapRows);

  /// The stored failures, newest first, once.
  Future<Result<List<StoredImportFailure>, CommyFailure>> readAll() {
    return StorageGuard.run(() async => _mapRows(await _ordered().get()));
  }

  /// Records [failures], redacting every line on the way in.
  Future<Result<void, CommyFailure>> recordAll(
    List<ImportFailure> failures, {
    DateTime? at,
  }) {
    return StorageGuard.runVoid(() async {
      if (failures.isEmpty) {
        return;
      }
      final timestamp = at ?? DateTime.now();
      await _db.batch((batch) {
        batch.insertAll(
          _db.importFailureRows,
          <ImportFailureRowsCompanion>[
            for (final failure in failures)
              ImportFailureRowsCompanion(
                id: Value<String>(_ids.newId()),
                // The one line in this file that rule R2 hangs off.
                redactedSnippet: Value<String>(failure.redactedLine),
                reason: Value<String>(failure.reason),
                createdAt: Value<DateTime>(timestamp),
              ),
          ],
        );
      });
      await _trim();
    });
  }

  /// Empties the list.
  Future<Result<void, CommyFailure>> clear() {
    return StorageGuard.runVoid(() async {
      await _db.delete(_db.importFailureRows).go();
    });
  }

  Future<void> _trim() async {
    final survivors = await (_ordered()..limit(retainedCount)).get();
    if (survivors.length < retainedCount) {
      return;
    }
    final keep = survivors.map((row) => row.id).toList();
    await (_db.delete(_db.importFailureRows)
          ..where((table) => table.id.isNotIn(keep)))
        .go();
  }

  SimpleSelectStatement<$ImportFailureRowsTable, ImportFailureRow> _ordered() {
    return _db.select(_db.importFailureRows)
      ..orderBy(<OrderClauseGenerator<$ImportFailureRowsTable>>[
        (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.desc,
            ),
      ]);
  }

  static List<StoredImportFailure> _mapRows(List<ImportFailureRow> rows) {
    return rows
        .map(
          (row) => StoredImportFailure(
            id: row.id,
            redactedLine: row.redactedSnippet,
            reason: row.reason,
            createdAt: row.createdAt,
          ),
        )
        .toList();
  }
}
