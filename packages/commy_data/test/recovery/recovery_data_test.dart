import 'dart:convert';
import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_adapter.dart';
import '../support/test_stack.dart';

/// The data half of docs/adr/0019-subscription-domain-recovery.md: the
/// signature check against a vector made by Go's own `crypto/ed25519`, the
/// meeting point's request, and the schema version that stores what was
/// learnt.
void main() {
  final vector = jsonDecode(
    File('test/recovery/fixtures/manifest_vector.json').readAsStringSync(),
  ) as Map<String, Object?>;

  group('Ed25519SignatureVerifier', () {
    // The same string the Commy Cloud server signs and checks in its own
    // tests: two implementations agreeing on one vector is the only proof
    // that a manifest signed in the dashboard opens on the phone.
    test('believes the Go-signed vector and the reader agrees', () async {
      const reader = ManifestReader(verifier: Ed25519SignatureVerifier());

      final manifest = await reader.read(vector['compact']! as String);

      expect(manifest, isNotNull);
      expect(manifest?.id, 'axm');
      expect(manifest?.seq, 3);
      expect(manifest?.key, vector['public_key']);
      expect(manifest?.nextKey, vector['next_key']);
    });

    test('refuses the vector with its payload changed', () async {
      const reader = ManifestReader(verifier: Ed25519SignatureVerifier());

      expect(await reader.read(vector['tampered']! as String), isNull);
    });

    test('a malformed key or signature is false, not a throw', () async {
      const verifier = Ed25519SignatureVerifier();

      expect(
        await verifier.verifyEd25519(
          publicKey: <int>[1, 2, 3],
          message: <int>[1],
          signature: List<int>.filled(64, 0),
        ),
        isFalse,
      );
      expect(
        await verifier.verifyEd25519(
          publicKey: List<int>.filled(32, 0),
          message: <int>[1],
          signature: <int>[0],
        ),
        isFalse,
      );
    });
  });

  group('HttpRendezvousFetcher', () {
    HttpRendezvousFetcher fetcherWith(StubHttpAdapter adapter) =>
        HttpRendezvousFetcher(
          client: CommyHttpClient(
            userAgent: 'Commy/1.0.0',
            directClient: Dio()..httpClientAdapter = adapter,
          ),
        );
    final point = Uri.parse('https://commy.example.net/r/axm');

    test('carries the manifest and nothing that names the user', () async {
      final adapter = StubHttpAdapter.text('${vector['compact']}\n');

      final result = await fetcherWith(adapter).fetch(point);

      expect(result.valueOrNull, vector['compact']);
      final headers = adapter.requests.single.headers.map(
        (key, value) => MapEntry(key.toLowerCase(), '$value'),
      );
      expect(headers['user-agent'], 'Commy/1.0.0');
      for (final name in <String>[
        'x-hwid',
        'x-device-os',
        'x-ver-os',
        'x-device-model',
        'cookie',
        'authorization',
      ]) {
        expect(headers.containsKey(name), isFalse, reason: name);
      }
    });

    test('an answer the size of a page, not a manifest, is refused', () async {
      final result = await fetcherWith(
        StubHttpAdapter.text('<html>${'x' * 5000}</html>'),
      ).fetch(point);

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    });

    test('a meeting point over plain http is not asked at all', () async {
      final adapter = StubHttpAdapter.text('v1.a.b');

      final result = await fetcherWith(adapter)
          .fetch(Uri.parse('http://commy.example.net/r/axm'));

      expect(result.failureOrNull, isNotNull);
      expect(adapter.requests, isEmpty);
    });

    test('a refusal is a failure', () async {
      final result = await fetcherWith(
        StubHttpAdapter.text('not found', statusCode: 404),
      ).fetch(point);

      expect(result.failureOrNull, isNotNull);
    });
  });

  group('schema version 2', () {
    test('a v1 database gains the column and keeps its cards', () async {
      final v1 = File('test/database/fixtures/schema_v1.sql')
          .readAsStringSync()
          .split(';\n')
          .map((statement) => statement.trim())
          .where((statement) => statement.isNotEmpty);
      final database = CommyDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            v1.forEach(raw.execute);
            raw
              ..execute(
                'INSERT INTO subscriptions (id, name, url_ref, redacted_url) '
                "VALUES ('s1', 'Old card', 'ref', 'https://sub.example.com')",
              )
              ..execute('PRAGMA user_version = 1');
          },
        ),
      );
      addTearDown(database.close);

      final rows = await database.select(database.subscriptionRows).get();

      expect(database.schemaVersion, 2);
      expect(rows.single.name, 'Old card');
      expect(rows.single.recoveryJson, isNull);
      final columns =
          await database.customSelect('PRAGMA table_info(subscriptions)').get();
      expect(
        columns.map((row) => row.read<String>('name')),
        contains('recovery_json'),
      );
    });

    test('a card stores and reads back what recovery learnt', () async {
      final stack = TestStack.create();
      addTearDown(stack.dispose);
      final manifest =
          SignedManifest.parse(vector['compact']! as String)!.manifest;
      final recovery = SubscriptionRecovery.pinned(manifest).copyWith(
        lastRendezvousAt: DateTime.utc(2026, 10, 5, 12),
        enabled: false,
      );
      final subscription = Subscription(
        id: 's1',
        name: 'Panel',
        url: Uri.parse('https://sub.example.com/sub/TOKEN'),
        recovery: recovery,
      );

      await stack.subscriptions.upsert(subscription);
      final back = (await stack.subscriptions.findById('s1')).valueOrNull;

      expect(back?.recovery, recovery);
      // Rule R2 holds: the token is in the keystore, not beside the state.
      final values = await stack.dumpAllValues();
      expect(values.any((value) => value.contains('TOKEN')), isFalse);
    });

    test('a state that does not read costs the state, not the card', () async {
      final stack = TestStack.create();
      addTearDown(stack.dispose);
      await stack.subscriptions.upsert(
        Subscription(
          id: 's1',
          name: 'Panel',
          url: Uri.parse('https://sub.example.com/sub/TOKEN'),
        ),
      );
      await (stack.database.update(stack.database.subscriptionRows)
            ..where((table) => table.id.equals('s1')))
          .write(
        const SubscriptionRowsCompanion(recoveryJson: Value<String?>('{oops')),
      );

      final back = (await stack.subscriptions.findById('s1')).valueOrNull;

      expect(back?.name, 'Panel');
      expect(back?.recovery, isNull);
    });
  });
}
