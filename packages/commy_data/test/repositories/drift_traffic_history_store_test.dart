import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
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
  late TestStack stack;
  late DriftTrafficHistoryStore store;

  final day = DateTime(2026, 8, 4, 12);

  setUp(() {
    stack = TestStack.create();
    store = stack.traffic;
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftTrafficHistoryStore', () {
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
}
