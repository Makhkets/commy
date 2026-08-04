import 'package:drift/drift.dart';

/// Traffic totals, one row per calendar day and scope.
///
/// An aggregate, deliberately. Raw connections are never persisted
/// (docs/06-data-model.md): a per-connection history would be a browsing log,
/// and a client whose whole pitch is "we do not watch you" has no business
/// keeping one on disk.
@DataClassName('TrafficDayRow')
class TrafficDailyRows extends Table {
  /// Local calendar day as `YYYY-MM-DD`. See `DayKey`.
  TextColumn get day => text().withLength(min: 10, max: 10)();

  /// What the row counts: a node id, or the empty string for everything.
  TextColumn get scope => text().withDefault(const Constant(''))();

  /// Bytes sent that day.
  IntColumn get upBytes => integer().withDefault(const Constant(0))();

  /// Bytes received that day.
  IntColumn get downBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{day, scope};

  @override
  String get tableName => 'traffic_daily';
}
