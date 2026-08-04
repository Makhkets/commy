import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

/// The test docs/adr/0007-database-encryption.md makes mandatory:
///
/// > Тест, который это стережёт: дамп всех таблиц после импорта реальной
/// > подписки не должен содержать ни одного UUID, пароля или полного URL
/// > подписки. Этот тест обязателен — без него правило R2 держится на честном
/// > слове.
///
/// It scans the raw column values of every table, not the mapped objects: the
/// question is what ends up in the file, and a mapper that hides a leak from
/// itself is exactly the failure mode worth guarding against.
void main() {
  late TestStack stack;

  setUp(() => stack = TestStack.create());
  tearDown(() async {
    await stack.dispose();
  });

  Future<void> importSubscription() async {
    final subscription = Fixtures.subscription();
    await stack.subscriptions.upsert(subscription);
    await stack.nodes.replaceForSubscription(
      subscriptionId: subscription.id,
      nodes: <ProxyNode>[
        Fixtures.vlessNode(subscriptionId: subscription.id),
        Fixtures.trojanNode(subscriptionId: subscription.id, sortIndex: 1),
        Fixtures.socksNode(),
      ],
    );
    await stack.importFailures.recordAll(<ImportFailure>[
      const ImportFailure(
        rawLine: 'vless://${Fixtures.uuid}@bad.example.com:443#Broken',
        reason: 'unknown transport',
      ),
    ]);
  }

  test('no credential from a real-shaped import reaches any column', () async {
    await importSubscription();

    final dump = await stack.dumpAllValues();
    final joined = dump.join('\n');

    expect(joined, isNot(contains(Fixtures.uuid)));
    expect(joined, isNot(contains(Fixtures.password)));
    expect(joined, isNot(contains(Fixtures.shortId)));
    expect(joined, isNot(contains(Fixtures.subscriptionUrl.path)));
    expect(joined, isNot(contains(Fixtures.subscriptionUrl.query)));
  });

  test('the same credentials are present in the keystore', () async {
    await importSubscription();

    final secrets = stack.store.snapshot.values.join('\n');

    expect(secrets, contains(Fixtures.uuid));
    expect(secrets, contains(Fixtures.password));
    expect(secrets, contains(Fixtures.shortId));
    expect(secrets, contains(Fixtures.subscriptionUrl.toString()));
  });

  test('the node row keeps the transport half in the clear', () async {
    await importSubscription();

    final dump = (await stack.dumpAllValues()).join('\n');

    // Not secrets, and useful: the config generator needs them and the leak
    // model in the ADR accepts them explicitly.
    expect(dump, contains('www.microsoft.com'));
    expect(dump, contains('de1.vpn.example.com'));
  });

  test('an import failure is stored redacted, never raw', () async {
    await importSubscription();

    final stored = (await stack.importFailures.readAll()).valueOrNull!;

    expect(stored, hasLength(1));
    expect(stored.single.redactedLine, isNot(contains(Fixtures.uuid)));
    expect(stored.single.redactedLine, contains('bad.example.com'));
    expect(stored.single.reason, equals('unknown transport'));
  });

  test('a node with no credentials gets no keystore entry', () async {
    await stack.nodes.upsertAll(<ProxyNode>[Fixtures.socksNode()]);

    final keys = stack.store.snapshot.keys;

    expect(keys, isNot(contains(SecretKeys.nodeParams('node-socks'))));
  });
}
