import 'package:drift/drift.dart';

/// Entries an import could not understand, kept so the user can see why.
///
/// Partial success is success: forty nodes out of fifty are imported and the
/// remaining ten land here with a reason (docs/06-data-model.md).
///
/// Rule R2 has a sharp edge on this table. `ImportFailure.rawLine` is the line
/// the user pasted, so it usually *is* a working `vless://` link with a live
/// uuid in it. Only `ImportFailure.redactedLine` is ever written to
/// [redactedSnippet]; the raw line never reaches the disk at all.
@DataClassName('ImportFailureRow')
class ImportFailureRows extends Table {
  /// Stable identifier.
  TextColumn get id => text()();

  /// The offending line with its credentials already blanked.
  TextColumn get redactedSnippet => text()();

  /// Why it failed, in words the user can act on.
  TextColumn get reason => text()();

  /// When the import ran.
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'import_failures';
}
