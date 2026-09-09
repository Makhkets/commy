import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uuid = '7f3c1a2b-4d5e-6f70-8192-a3b4c5d6e7f8';

  AppLogger build({
    int capacity = AppLogger.defaultCapacity,
    LogLevel minimumLevel = LogLevel.trace,
    LogRedaction? redact,
  }) =>
      AppLogger(
        capacity: capacity,
        minimumLevel: minimumLevel,
        redact: redact ?? DefaultLogRedaction.apply,
        clock: () => DateTime.utc(2026, 8, 4, 12, 4, 31, 7),
        // Silent: the default sink writes to the platform log viewer, which in
        // a test run is just noise.
        sink: (_) {},
      );

  group('AppLogger levels', () {
    test('drops anything quieter than the threshold', () {
      final logger = build(minimumLevel: LogLevel.warn)
        ..debug('chatter')
        ..info('still chatter')
        ..warn('this one counts')
        ..error('and this one');

      expect(logger.buffer.map((line) => line.message), <String>[
        'this one counts',
        'and this one',
      ]);
    });

    test('follows the threshold when it moves at runtime', () {
      final logger = build(minimumLevel: LogLevel.error)
        ..info('dropped')
        ..minimumLevel = LogLevel.info
        ..info('kept');

      expect(logger.buffer.single.message, 'kept');
    });

    test('records the level each helper stands for', () {
      final logger = build()
        ..trace('a')
        ..debug('b')
        ..info('c')
        ..warn('d')
        ..error('e')
        ..fatal('f');

      expect(logger.buffer.map((line) => line.level), <LogLevel>[
        LogLevel.trace,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warn,
        LogLevel.error,
        LogLevel.fatal,
      ]);
    });
  });

  group('AppLogger ring buffer', () {
    test('keeps the newest lines and drops the oldest', () {
      final logger = build(capacity: 3);
      for (var index = 0; index < 6; index++) {
        logger.info('line $index');
      }

      expect(logger.length, 3);
      expect(logger.buffer.map((line) => line.message), <String>[
        'line 3',
        'line 4',
        'line 5',
      ]);
    });

    test('hands out a copy nobody can mutate underneath it', () {
      final logger = build()..info('one');

      expect(() => logger.buffer.add(logger.buffer.first), throwsA(anything));
    });

    test('clear empties the buffer', () {
      final logger = build()
        ..info('one')
        ..clear();

      expect(logger.buffer, isEmpty);
    });
  });

  group('AppLogger redaction', () {
    test('scrubs before the line reaches the buffer', () {
      final logger = build()..info('dial failed for $uuid');

      expect(logger.buffer.single.message, isNot(contains(uuid)));
      expect(logger.buffer.single.message, contains(Redact.placeholder));
    });

    test('scrubs before the line reaches a subscriber', () async {
      final logger = build();
      final seen = <LogLine>[];
      final subscription = logger.lines.listen(seen.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);

      logger
        ..info('dial failed for $uuid')
        ..info('done');
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      expect(seen.first.message, isNot(contains(uuid)));
    });

    test('scrubs an exception folded into the message', () {
      const url = 'https://panel.example.com/sub/tok3n-in-the-path';
      final logger = build()
        ..error('sync failed', error: Exception('GET $url timed out'));

      expect(logger.buffer.single.message, isNot(contains('tok3n')));
      expect(logger.buffer.single.message, contains('sync failed'));
    });

    test('scrubs a line handed over whole by the core stream', () {
      final logger = build()
        ..add(
          LogLine(
            level: LogLevel.warn,
            message: 'outbound: user $uuid rejected',
            at: DateTime.utc(2026, 8, 4),
            tag: 'router',
          ),
        );

      expect(logger.buffer.single.message, isNot(contains(uuid)));
      expect(logger.buffer.single.tag, 'router');
    });

    test('export carries nothing the buffer did not already scrub', () {
      final logger = build()..info('dial failed for $uuid', tag: 'outbound');

      expect(logger.export(), isNot(contains(uuid)));
      expect(logger.export(), contains('outbound'));
      expect(logger.export(), contains('INFO'));
    });

    test('takes an injected redactor instead of the default one', () {
      final logger = build(redact: (message) => 'X')..info('anything');

      expect(logger.buffer.single.message, 'X');
    });
  });

  group('AppLogger stream', () {
    test('is broadcast, so both the screen and the sink can listen', () {
      final logger = build();
      final first = <LogLine>[];
      final second = <LogLine>[];
      final a = logger.lines.listen(first.add);
      final b = logger.lines.listen(second.add);
      addTearDown(() async {
        await a.cancel();
        await b.cancel();
      });

      expect(logger.lines.isBroadcast, isTrue);
    });

    test('a line written with no subscriber is still buffered', () {
      final logger = build()..info('nobody is listening');

      expect(logger.buffer, hasLength(1));
    });

    test(
        'a snapshot taken before subscribing and the stream after it are '
        'disjoint', () async {
      // The contract the app's log pump rests on when it replays the ring
      // without deduplicating: read `buffer`, then listen, in one synchronous
      // block, and no line can land on both sides.
      final logger = build()..info('before');
      final seen = <LogLine>[];

      final backlog = logger.buffer;
      final subscription = logger.lines.listen(seen.add);
      addTearDown(subscription.cancel);
      logger.info('after');
      await Future<void>.delayed(Duration.zero);

      expect(backlog.map((line) => line.message), <String>['before']);
      expect(seen.map((line) => line.message), <String>['after']);
    });
  });

  group('AppLogger lifecycle', () {
    test('ignores writes after dispose instead of throwing', () async {
      final logger = build()..info('before');
      await logger.dispose();
      logger.info('after');

      expect(logger.isDisposed, isTrue);
      expect(logger.buffer, isEmpty);
    });

    test('dispose is idempotent', () async {
      final logger = build();
      await logger.dispose();

      await expectLater(logger.dispose(), completes);
    });
  });

  group('AppLogger.format', () {
    test('puts time, level, tag and message in a fixed order', () {
      final line = LogLine(
        level: LogLevel.warn,
        message: 'something',
        at: DateTime.utc(2026, 8, 4, 12, 4, 31, 7).toLocal(),
        tag: 'router',
      );

      expect(AppLogger.format(line), endsWith('WARN router something'));
    });

    test('omits the tag when there is none', () {
      final line = LogLine(
        level: LogLevel.info,
        message: 'something',
        at: DateTime.utc(2026, 8, 4).toLocal(),
      );

      expect(AppLogger.format(line), endsWith('INFO something'));
    });
  });
}
