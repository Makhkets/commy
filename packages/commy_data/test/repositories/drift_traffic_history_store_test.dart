import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_stack.dart';

TrafficSample sample({
  required int up,
  required int down,
  required DateTime at,
}) =>
    TrafficSample(
      uplink: 0,
      downlink: 0,
      uplinkTotal: up,
      downlinkTotal: down,
      at: at,
    );

void main() {
  final day = DateTime(2026, 8, 4, 12);

  group('DriftTrafficHistoryStore', () {
    late TestStack stack;
    late DriftTrafficHistoryStore store;

    setUp(() {
      stack = TestStack.create();
      store = stack.traffic;
    });
    tearDown(() async {
      await stack.dispose();
    });

    test('addDelta accumulates into one bucket per day', () async {
      await store.addDelta(day: day, upBytes: 100, downBytes: 200);
      await store.addDelta(day: day, upBytes: 50, downBytes: 25);

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days, hasLength(1));
      expect(days.single.upBytes, equals(150));
      expect(days.single.downBytes, equals(225));
      expect(days.single.totalBytes, equals(375));
    });

    test('different days get different buckets', () async {
      await store.addDelta(day: day, upBytes: 10, downBytes: 10);
      await store.addDelta(
        day: day.add(const Duration(days: 1)),
        upBytes: 20,
        downBytes: 20,
      );

      final days = (await store.readRange(
        from: day,
        to: day.add(const Duration(days: 1)),
      ))
          .valueOrNull!;

      expect(days, hasLength(2));
      expect(days.first.upBytes, equals(10));
      expect(days.last.upBytes, equals(20));
    });

    test('a range excludes days outside it', () async {
      await store.addDelta(
        day: day.subtract(const Duration(days: 5)),
        upBytes: 1,
        downBytes: 1,
      );
      await store.addDelta(day: day, upBytes: 2, downBytes: 2);

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days, hasLength(1));
      expect(days.single.upBytes, equals(2));
    });

    test('the first sample only establishes a baseline', () async {
      await store.recordSample(sample(up: 1000, down: 2000, at: day));

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days, isEmpty);
    });

    test('later samples record the difference, not the counter', () async {
      await store.recordSample(sample(up: 1000, down: 2000, at: day));
      await store.recordSample(sample(up: 1500, down: 2500, at: day));

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days.single.upBytes, equals(500));
      expect(days.single.downBytes, equals(500));
    });

    test('a counter that went backwards means the core restarted', () async {
      await store.recordSample(sample(up: 5000, down: 5000, at: day));
      await store.recordSample(sample(up: 120, down: 340, at: day));

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days.single.upBytes, equals(120));
      expect(days.single.downBytes, equals(340));
    });

    test('resetSession forgets the baseline', () async {
      await store.recordSample(sample(up: 1000, down: 1000, at: day));
      store.resetSession();
      await store.recordSample(sample(up: 300, down: 300, at: day));

      final days = (await store.readRange(from: day, to: day)).valueOrNull!;

      expect(days, isEmpty);
    });

    test('scopes are kept apart', () async {
      await store.addDelta(day: day, upBytes: 10, downBytes: 0);
      await store.addDelta(
        day: day,
        upBytes: 99,
        downBytes: 0,
        scope: 'node-1',
      );

      final all = (await store.readRange(from: day, to: day)).valueOrNull!;
      final node = (await store.readRange(
        from: day,
        to: day,
        scope: 'node-1',
      ))
          .valueOrNull!;

      expect(all.single.upBytes, equals(10));
      expect(node.single.upBytes, equals(99));
    });

    test('clear empties the history', () async {
      await store.addDelta(day: day, upBytes: 10, downBytes: 10);
      await store.clear();

      expect(
        (await store.readRange(from: day, to: day)).valueOrNull,
        isEmpty,
      );
    });
  });

  // The core ticks once a second, in the background too. A write per tick was
  // a committed transaction — a WAL append and an fsync — every second the
  // tunnel carried anything, to move two counters a day.
  group('DriftTrafficHistoryStore batching', () {
    late CommitCounter commits;
    late CommyDatabase database;
    late DriftTrafficHistoryStore batched;

    // One tick a second from [start], each moving 1000 bytes up and 2000
    // down, the counters starting from zero like a fresh session.
    Future<void> tick(int seconds, {DateTime? start}) async {
      final origin = start ?? day;
      for (var second = 0; second <= seconds; second++) {
        await batched.recordSample(
          sample(
            up: 1000 * second,
            down: 2000 * second,
            at: origin.add(Duration(seconds: second)),
          ),
        );
      }
    }

    Future<List<TrafficDayRow>> rowsOnDisk() =>
        database.select(database.trafficDailyRows).get();

    setUp(() async {
      commits = CommitCounter();
      database = CommyDatabase(NativeDatabase.memory().interceptWith(commits));
      batched = DriftTrafficHistoryStore(database: database);
      // Opening runs the migration; only what the store commits counts.
      await rowsOnDisk();
      commits.count = 0;
    });
    tearDown(() async {
      await database.close();
    });

    test('a minute of ticks commits nothing', () async {
      // Sixty ticks with bytes in every one: sixty transactions before.
      await tick(60);

      expect(commits.count, equals(0));
      expect(await rowsOnDisk(), isEmpty);
    });

    test('the tick a minute on writes the whole batch in one transaction',
        () async {
      await tick(61);

      expect(commits.count, equals(1));
      final row = (await rowsOnDisk()).single;
      // The same bytes a write per tick would have stored: every delta since
      // the baseline at second zero.
      expect(row.upBytes, equals(61 * 1000));
      expect(row.downBytes, equals(61 * 2000));
    });

    test('flush writes what is waiting, once', () async {
      await tick(10);

      await batched.flush();
      await batched.flush();

      expect(commits.count, equals(1));
      final row = (await rowsOnDisk()).single;
      expect(row.upBytes, equals(10 * 1000));
      expect(row.downBytes, equals(10 * 2000));
    });

    test('a batch across midnight lands in both days', () async {
      final evening = DateTime(2026, 8, 4, 23, 59, 50);
      await tick(20, start: evening);
      await batched.flush();

      expect(commits.count, equals(1));
      final rows = await rowsOnDisk();
      final byDay = <String, TrafficDayRow>{
        for (final row in rows) row.day: row,
      };
      // Seconds 1..9 are the 4th, 10..20 are the 5th.
      expect(byDay['2026-08-04']!.upBytes, equals(9 * 1000));
      expect(byDay['2026-08-05']!.upBytes, equals(11 * 1000));
    });

    test('reads see bytes that are still waiting', () async {
      await tick(5);

      final read = (await batched.readRange(from: day, to: day)).valueOrNull!;
      final watched = await batched.watchRange(from: day, to: day).first;

      expect(read.single.upBytes, equals(5 * 1000));
      expect(watched.single.downBytes, equals(5 * 2000));
    });

    test('clear drops the batch with the history', () async {
      await tick(5);

      await batched.clear();
      await batched.flush();

      expect(await rowsOnDisk(), isEmpty);
    });
  });
}

/// Counts committed transactions: each one is a WAL append and an fsync.
class CommitCounter extends QueryInterceptor {
  /// Commits since the last reset.
  int count = 0;

  @override
  Future<void> commitTransaction(TransactionExecutor inner) {
    count++;
    return super.commitTransaction(inner);
  }
}
