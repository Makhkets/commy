import 'package:drift/drift.dart';

/// One routing rule. Order matters: the first match wins.
///
/// The rest of `RoutingPolicy` — mode, per-app lists, LAN bypass, ad blocking —
/// is a single small object and lives in the settings table instead of getting
/// a column each. Rules are a list the user edits and reorders, so they get a
/// table.
@DataClassName('RoutingRuleRow')
class RoutingRuleRows extends Table {
  /// Stable identifier.
  TextColumn get id => text()();

  /// What the rule matches, in the core's own syntax.
  TextColumn get matcher => text()();

  /// `RuleAction.name`.
  TextColumn get action => text()();

  /// Position in the list. Lower runs first.
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// Whether the rule is currently applied.
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};

  @override
  String get tableName => 'routing_rules';
}
