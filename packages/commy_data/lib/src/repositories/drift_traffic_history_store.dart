import 'package:commy_data/src/database/commy_database.dart';
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
///
/// The deltas wait in memory and are written once per [flushInterval], not
/// once a tick. The core ticks every second, in the background too, and a
/// write per tick was a committed transaction — a WAL append and an fsync —
/// every second the tunnel carried anything, to move two counters a day
/// (rule R11). Reads write the batch first, so they never miss a byte.
class DriftTrafficHistoryStore implements TrafficHistoryRepository {
  /// Creates the store.
  DriftTrafficHistoryStore({required CommyDatabase database}) : _db = database;

  /// How long a counted byte may wait in memory before it is written.
  ///
  /// Measured on the samples' own clock, so the store needs no timer. A
  /// minute is invisible on a screen of daily totals, and it is also the most
  /// an abrupt end of the process can take with it: the tunnel going down and
  /// the app leaving the foreground both call [flush].
  static const Duration flushInterval = Duration(minutes: 1);

  final CommyDatabase _db;

  TrafficSample? _previous;

  /// Bytes counted but not written yet, up and down, by day key and scope.
  ///
  /// Keyed by day rather than one running pair, so a batch that spans
  /// midnight still lands in the two days the bytes moved in.
  final Map<(String, String), (int, int)> _pending =
      <(String, String), (int, int)>{};

  /// When the oldest byte in [_pending] was counted.
  DateTime? _pendingSince;

  /// Adds the difference between [sample] and the previous one.
  ///
  /// [scope] is a node id, or `TrafficDay.allScope` for the unattributed total.
  /// Call it with every tick the core emits; the first tick of a session only
  /// establishes the baseline and stores nothing. The difference joins the
  /// batch in memory, and the batch is written by the first tick that comes
  /// [flushInterval] after its oldest byte.
  @override
  Future<Result<void, CommyFailure>> recordSample(
    TrafficSample sample, {
    String scope = TrafficDay.allScope,
  }) async {
    final previous = _previous;
    _previous = sample;
    if (previous != null) {
      final upDelta = _delta(previous.uplinkTotal, sample.uplinkTotal);
      final downDelta = _delta(previous.downlinkTotal, sample.downlinkTotal);
      if (upDelta != 0 || downDelta != 0) {
        final key = (DayKey.of(sample.at), scope);
        final (up, down) = _pending[key] ?? (0, 0);
        _pending[key] = (up + upDelta, down + downDelta);
        _pendingSince ??= sample.at;
      }
    }
    final since = _pendingSince;
    if (since == null) {
      return const Ok<void, CommyFailure>(null);
    }
    final waited = sample.at.difference(since);
    // A clock set back is no reason to hold the batch until it catches up.
    if (waited < flushInterval && !waited.isNegative) {
      return const Ok<void, CommyFailure>(null);
    }
    return flush();
  }

  /// Forgets the baseline. Call it when the tunnel goes down.
  ///
  /// The batch is left to [flush]: it holds bytes that did move, and the next
  /// session's can join it without harm.
  @override
  void resetSession() => _previous = null;

  /// Writes the bytes counted since the last write, in one transaction.
  @override
  Future<Result<void, CommyFailure>> flush() {
    if (_pending.isEmpty) {
      return Future<Result<void, CommyFailure>>.value(
        const Ok<void, CommyFailure>(null),
      );
    }
    // Taken out before the first await: a tick that lands while the
    // transaction runs starts the next batch instead of being written twice.
    final batch = Map<(String, String), (int, int)>.of(_pending);
    _pending.clear();
    _pendingSince = null;
    return StorageGuard.runVoid(() async {
      await _db.transaction(() async {
        for (final MapEntry(key: (day, scope), value: (up, down))
            in batch.entries) {
          await _add(day: day, scope: scope, upBytes: up, downBytes: down);
        }
      });
    });
  }

  /// Adds [upBytes] and [downBytes] to the bucket of [day], right away.
  Future<Result<void, CommyFailure>> addDelta({
    required DateTime day,
    required int upBytes,
    required int downBytes,
    String scope = TrafficDay.allScope,
  }) {
    return StorageGuard.runVoid(() async {
      await _db.transaction(
        () => _add(
          day: DayKey.of(day),
          scope: scope,
          upBytes: upBytes,
          downBytes: downBytes,
        ),
      );
    });
  }

  /// Adds to the bucket of one day key. Runs inside the caller's transaction.
  Future<void> _add({
    required String day,
    required String scope,
    required int upBytes,
    required int downBytes,
  }) async {
    final existing = await (_db.select(_db.trafficDailyRows)
          ..where(
            (table) => table.day.equals(day) & table.scope.equals(scope),
          ))
        .getSingleOrNull();
    await _db.into(_db.trafficDailyRows).insertOnConflictUpdate(
          TrafficDailyRowsCompanion(
            day: Value<String>(day),
            scope: Value<String>(scope),
            upBytes: Value<int>((existing?.upBytes ?? 0) + upBytes),
            downBytes: Value<int>((existing?.downBytes ?? 0) + downBytes),
          ),
        );
  }

  /// The days from [from] to [to] inclusive, oldest first.
  @override
  Future<Result<List<TrafficDay>, CommyFailure>> readRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  }) {
    return StorageGuard.run(() async {
      // A batch that could not be written is gone either way; the read still
      // reports what the file holds.
      await flush();
      final query = _rangeQuery(from: from, to: to, scope: scope);
      return _mapRows(await query.get());
    });
  }

  /// The days from [from] to [to] inclusive, refreshed on every write.
  ///
  /// The batch is written first, so the screen opens on the true total; after
  /// that the numbers move once per [flushInterval], which a day's total can
  /// afford.
  @override
  Stream<List<TrafficDay>> watchRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  }) async* {
    await flush();
    yield* _rangeQuery(from: from, to: to, scope: scope).watch().map(_mapRows);
  }

  /// Drops every recorded day. Part of "erase all data".
  @override
  Future<Result<void, CommyFailure>> clear() {
    // The batch belongs to the history being erased: left in memory, the
    // next write would put part of today back.
    _pending.clear();
    _pendingSince = null;
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
