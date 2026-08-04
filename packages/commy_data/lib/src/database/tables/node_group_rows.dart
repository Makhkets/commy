import 'package:drift/drift.dart';

/// A folder for nodes the user added by hand.
///
/// Nothing here is sensitive: a group is a name and a position.
@DataClassName('NodeGroupRow')
class NodeGroupRows extends Table {
  /// Stable identifier.
  TextColumn get id => text()();

  /// Display name.
  TextColumn get name => text()();

  /// Position in the list on the main screen.
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Whether the group is folded away in the UI.
  BoolColumn get isCollapsed => boolean().withDefault(const Constant(false))();

  /// When the group was created.
  DateTimeColumn get createdAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'node_groups';
}
