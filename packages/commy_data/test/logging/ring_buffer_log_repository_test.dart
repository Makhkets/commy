import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

LogLine line(String message, {int second = 0}) => LogLine(
      level: LogLevel.info,
      message: message,
      at: DateTime.utc(2026, 8, 4, 12, 0, second),
      tag: 'core',
    );

void main() {
  group('RingBufferLogRepository', () {
    test('read returns lines with credentials already removed', () async {
      final repository = RingBufferLogRepository();
      await repository.append(line('uuid=${Fixtures.uuid}'));

      final result = await repository.read();
      final lines = result.valueOrNull!;

      expect(lines, hasLength(1));
      expect(lines.single.message, isNot(contains(Fixtures.uuid)));
      await repository.dispose();
    });

    test('drops the oldest line once the capacity is reached', () async {
      final repository = RingBufferLogRepository(capacity: 3);
      for (var i = 0; i < 5; i++) {
        await repository.append(line('line $i', second: i));
      }

      final lines = (await repository.read()).valueOrNull!;
      final messages = lines.map((entry) => entry.message).toList();

      expect(messages, equals(<String>['line 2', 'line 3', 'line 4']));
      await repository.dispose();
    });

    test('read honours a limit by keeping the newest lines', () async {
      final repository = RingBufferLogRepository();
      for (var i = 0; i < 5; i++) {
        await repository.append(line('line $i', second: i));
      }

      final lines = (await repository.read(limit: 2)).valueOrNull!;
      final messages = lines.map((entry) => entry.message).toList();

      expect(messages, equals(<String>['line 3', 'line 4']));
      await repository.dispose();
    });

    test('watch emits the current buffer immediately', () async {
      final repository = RingBufferLogRepository();
      await repository.append(line('first'));

      final snapshot = await repository.watch().first;

      expect(snapshot, hasLength(1));
      expect(snapshot.single.message, equals('first'));
      await repository.dispose();
    });

    test('watch emits again on every append', () async {
      final repository = RingBufferLogRepository();
      final seen = <int>[];
      final subscription =
          repository.watch().listen((lines) => seen.add(lines.length));
      await Future<void>.delayed(Duration.zero);

      await repository.append(line('a'));
      await Future<void>.delayed(Duration.zero);
      await repository.append(line('b'));
      await Future<void>.delayed(Duration.zero);

      expect(seen, containsAllInOrder(<int>[0, 1, 2]));
      await subscription.cancel();
      await repository.dispose();
    });

    test('clear empties the buffer', () async {
      final repository = RingBufferLogRepository();
      await repository.append(line('a'));
      await repository.clear();

      expect((await repository.read()).valueOrNull, isEmpty);
      await repository.dispose();
    });

    test('a redacted export hides both credentials and servers', () async {
      final repository = RingBufferLogRepository(
        redactor: LogRedactor(
          serverHosts: () => <String>['de1.vpn.example.com'],
        ),
      );
      await repository.append(
        line('dial vless://${Fixtures.uuid}@de1.vpn.example.com:443'),
      );

      final text = (await repository.export(redact: true)).valueOrNull!;

      expect(text, isNot(contains(Fixtures.uuid)));
      expect(text, isNot(contains('de1.vpn.example.com')));
      expect(text, contains(Redact.serverPlaceholder));
      await repository.dispose();
    });

    test('an unredacted export returns the raw buffer', () async {
      final repository = RingBufferLogRepository();
      await repository.append(line('uuid=${Fixtures.uuid}'));

      final text = (await repository.export(redact: false)).valueOrNull!;

      expect(text, contains(Fixtures.uuid));
      await repository.dispose();
    });

    test('an export carries the level, the time and the tag', () async {
      final repository = RingBufferLogRepository();
      await repository.append(line('hello'));

      final text = (await repository.export(redact: true)).valueOrNull!;

      expect(text, contains('INFO'));
      expect(text, contains('[core]'));
      expect(text, contains('2026-08-04T12:00:00.000Z'));
      await repository.dispose();
    });
  });
}
