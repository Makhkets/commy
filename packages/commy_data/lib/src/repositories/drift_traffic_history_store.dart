import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/models/traffic_day.dart';
import 'package:commy_data/src/util/day_key.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Daily traffic totals, for the statistics screen.
///
/// The core reports cumulative counters that reset every time the tunnel comes
/// up, so what is persisted are *deltas*: [recordSample] takes consecutive
/// samples and adds the difference. A counter that went backwards means the
/// tunnel restarted, and the new value is taken as the delta.
///
/// Two numbers a day and nothing else. There is no per-connection table and
/// there will not be one — that would be a browsing history, which is the
/// artefact this project exists not to keep.
class DriftTrafficHistoryStore {
  /// Creates the store.
  DriftTrafficHistoryStore({required CommyDatabase database}) : _db = database;

  final CommyDatabase _db;

  TrafficSample? _previous;

  /// Adds the difference between [sample] and the previous one.
  ///
  /// [scope] is a node id, or `TrafficDay.allScope` for the unattributed total.
  /// Call it with every tick the core emits; the first tick of a session only
  /// establishes the baseline and stores nothing.
  Future<Result<void, CommyFailure>> recordSample(
    TrafficSample sample, {
    String scope = TrafficDay.allScope,
  }) async {
    final previous = _previous;
    _previous = sample;
    if (previous == null) {
      return const Ok<void, CommyFailure>(null);
    }
    final upDelta = _delta(previous.uplinkTotal, sample.uplinkTotal);
    final downDelta = _delta(previous.downlinkTotal, sample.downlinkTotal);
    if (upDelta == 0 && downDelta == 0) {
      return const Ok<void, CommyFailure>(null);
    }
    return addDelta(
      day: sample.at,
      scope: scope,
      upBytes: upDelta,
      downBytes: downDelta,
    );
  }

  /// Forgets the baseline. Call it when the tunnel goes down.
  void resetSession() => _previous = null;

  /// Adds [upBytes] and [downBytes] to the bucket of [day].
  Future<Result<void, CommyFailure>> addDelta({
    required DateTime day,
    required int upBytes,
    required int downBytes,
    String scope = TrafficDay.allScope,
  }) {
    return StorageGuard.runVoid(() async {
      final key = DayKey.of(day);
      await _db.transaction(() async {
        final existing = await (_db.select(_db.trafficDailyRows)
              ..where(
                (table) => table.day.equals(key) & table.scope.equals(scope),
              ))
            .getSingleOrNull();
        await _db.into(_db.trafficDailyRows).insertOnConflictUpdate(
              TrafficDailyRowsCompanion(
                day: Value<String>(key),
                scope: Value<String>(scope),
                upBytes: Value<int>((existing?.upBytes ?? 0) + upBytes),
                downBytes: Value<int>((existing?.downBytes ?? 0) + downBytes),
              ),
            );
      });
    });
  }

  /// The days from [from] to [to] inclusive, oldest first.
  Future<Result<List<TrafficDay>, CommyFailure>> readRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  }) {
    return StorageGuard.run(() async {
      final query = _rangeQuery(from: from, to: to, scope: scope);
      return _mapRows(await query.get());
    });
  }

  /// The days from [from] to [to] inclusive, refreshed on every change.
  Stream<List<TrafficDay>> watchRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  }) {
    return _rangeQuery(from: from, to: to, scope: scope).watch().map(_mapRows);
  }

  /// Drops every recorded day. Part of "erase all data".
  Future<Result<void, CommyFailure>> clear() {
    return StorageGuard.runVoid(() async {
      await _db.delete(_db.trafficDailyRows).go();
    });
  }

  // The type argument is the *generated* table class, `$TrafficDailyRowsTable`,
  // not the `TrafficDailyRows` declaration it is generated from. Using the
  // declaration compiles as far as the analyzer resolving `HasResultSet`, and
  // then every column access fails with "the getter 'day' isn't defined".
  SimpleSelectStatement<$TrafficDailyRowsTable, TrafficDayRow> _rangeQuery({
    required DateTime from,
    required DateTime to,
    required String scope,
  }) {
    final start = DayKey.of(from);
    final end = DayKey.of(to);
    return _db.select(_db.trafficDailyRows)
      ..where(
        (table) =>
            table.scope.equals(scope) &
            table.day.isBiggerOrEqualValue(start) &
            table.day.isSmallerOrEqualValue(end),
      )
      ..orderBy(<OrderClauseGenerator<$TrafficDailyRowsTable>>[
        (table) => OrderingTerm(expression: table.day),
      ]);
  }

  static List<TrafficDay> _mapRows(List<TrafficDayRow> rows) {
    final result = <TrafficDay>[];
    for (final row in rows) {
      final day = DayKey.parse(row.day);
      if (day == null) {
        continue;
      }
      result.add(
        TrafficDay(
          day: day,
          scope: row.scope,
          upBytes: row.upBytes,
          downBytes: row.downBytes,
        ),
      );
    }
    return result;
  }

  /// The bytes that moved between two cumulative readings.
  ///
  /// A counter that went backwards means the core restarted and started
  /// counting from zero, so the new reading *is* the delta.
  static int _delta(int previous, int current) {
    if (current < previous) {
      return current < 0 ? 0 : current;
    }
    return current - previous;
  }
}
