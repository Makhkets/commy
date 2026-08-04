import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

void main() {
  late TestStack stack;
  late DriftImportFailureStore store;

  setUp(() {
    stack = TestStack.create();
    store = stack.importFailures;
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftImportFailureStore', () {
    test('stores the redacted line and never the raw one', () async {
      await store.recordAll(<ImportFailure>[
        const ImportFailure(
          rawLine: 'vless://${Fixtures.uuid}@bad.example.com:443#Broken',
          reason: 'unsupported transport',
        ),
      ]);

      final stored = (await store.readAll()).valueOrNull!;
      final dump = (await stack.dumpAllValues()).join('\n');

      expect(stored, hasLength(1));
      expect(stored.single.redactedLine, isNot(contains(Fixtures.uuid)));
      expect(dump, isNot(contains(Fixtures.uuid)));
    });

    test('recording nothing is a no-op', () async {
      await store.recordAll(const <ImportFailure>[]);

      expect((await store.readAll()).valueOrNull, isEmpty);
    });

    test('the newest failures come first', () async {
      await store.recordAll(
        const <ImportFailure>[
          ImportFailure(rawLine: 'older', reason: 'older'),
        ],
        at: DateTime.utc(2026, 8, 3),
      );
      await store.recordAll(
        const <ImportFailure>[
          ImportFailure(rawLine: 'newer', reason: 'newer'),
        ],
        at: DateTime.utc(2026, 8, 4),
      );

      final stored = (await store.readAll()).valueOrNull!;

      expect(stored.first.reason, equals('newer'));
    });

    test('the list is capped', () async {
      final many = <ImportFailure>[
        for (var i = 0; i < DriftImportFailureStore.retainedCount + 20; i++)
          ImportFailure(rawLine: 'line $i', reason: 'reason $i'),
      ];
      await store.recordAll(many, at: DateTime.utc(2026, 8, 4));

      final stored = (await store.readAll()).valueOrNull!;

      expect(
        stored.length,
        lessThanOrEqualTo(DriftImportFailureStore.retainedCount),
      );
    });

    test('the domain view carries the redacted line, not a credential',
        () async {
      await store.recordAll(<ImportFailure>[
        const ImportFailure(
          rawLine: 'trojan://${Fixtures.password}@nl.example.com:443',
          reason: 'bad port',
        ),
      ]);

      final stored = (await store.readAll()).valueOrNull!;
      final domain = stored.single.toDomain();

      expect(domain.rawLine, isNot(contains(Fixtures.password)));
      expect(domain.reason, equals('bad port'));
    });

    test('clear empties the list', () async {
      await store.recordAll(const <ImportFailure>[
        ImportFailure(rawLine: 'x', reason: 'y'),
      ]);
      await store.clear();

      expect((await store.readAll()).valueOrNull, isEmpty);
    });
  });
}
