import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

void main() {
  late TestStack stack;

  setUp(() => stack = TestStack.create());
  tearDown(() async {
    await stack.dispose();
  });

  group('CommyDatabase', () {
    test('a fresh database is at schema version 1', () {
      expect(stack.database.schemaVersion, equals(1));
      expect(
        stack.database.schemaVersion,
        equals(CommyDatabase.currentSchemaVersion),
      );
    });

    test('onCreate builds every table the model needs', () async {
      final rows = await stack.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table'",
          )
          .get();
      final names = rows.map((row) => row.read<String>('name')).toSet();

      expect(
        names,
        containsAll(<String>[
          'subscriptions',
          'nodes',
          'node_groups',
          'routing_rules',
          'settings',
          'traffic_daily',
          'import_failures',
        ]),
      );
    });

    test('foreign keys are enforced on the connection', () async {
      final rows =
          await stack.database.customSelect('PRAGMA foreign_keys').get();

      expect(rows.single.data.values.first, equals(1));
    });

    test('deleting a subscription cascades to its nodes', () async {
      await stack.subscriptions.upsert(Fixtures.subscription());
      await stack.nodes.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(subscriptionId: 'sub-1'),
      ]);

      await stack.database.customStatement(
        "DELETE FROM subscriptions WHERE id = 'sub-1'",
      );
      final remaining = await stack.database
          .customSelect(
            'SELECT id FROM nodes',
          )
          .get();

      expect(remaining, isEmpty);
    });

    test('a node cannot point at a subscription that is not there', () async {
      Object? caught;
      try {
        await stack.database.customStatement(
          'INSERT INTO nodes (id, name, protocol, host, port, '
          'subscription_id, sort_index, public_params_json) '
          "VALUES ('n', 'n', 'vless', 'h', 443, 'ghost', 0, '{}')",
        );
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
    });

    test('clearAll empties every table but keeps the schema', () async {
      await stack.subscriptions.upsert(Fixtures.subscription());
      await stack.settings.write(AppSettings.defaults);

      await stack.database.clearAll();

      expect((await stack.subscriptions.getAll()).valueOrNull, isEmpty);
      expect(await stack.dumpAllValues(), isEmpty);
      expect(stack.database.schemaVersion, equals(1));
    });
  });

  group('DayKey', () {
    test('formats a local calendar day', () {
      expect(DayKey.of(DateTime(2026, 8, 4, 23, 59)), equals('2026-08-04'));
      expect(DayKey.of(DateTime(2026)), equals('2026-01-01'));
    });

    test('parses back to local midnight', () {
      expect(DayKey.parse('2026-08-04'), equals(DateTime(2026, 8, 4)));
    });

    test('refuses a malformed key', () {
      expect(DayKey.parse('4 August'), isNull);
      expect(DayKey.parse('20260804'), isNull);
    });
  });

  group('RandomIdGenerator', () {
    test('produces a v4 uuid', () {
      final id = RandomIdGenerator().newId();

      expect(
        RegExp(
          '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}'
          r'-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'got $id',
      );
    });

    test('does not repeat itself', () {
      final generator = RandomIdGenerator();
      final ids = <String>{for (var i = 0; i < 500; i++) generator.newId()};

      expect(ids, hasLength(500));
    });
  });
}
