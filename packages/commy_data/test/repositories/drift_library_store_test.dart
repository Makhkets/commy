import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

void main() {
  late TestStack stack;
  late DriftLibraryStore store;

  final newSubscriptionUrl =
      Uri.parse('https://other.example.net/sub/0123456789abcdef');

  Subscription newSubscription() => Subscription(
        id: 'sub-new',
        name: 'Restored panel',
        url: newSubscriptionUrl,
      );

  setUp(() async {
    stack = TestStack.create();
    store = DriftLibraryStore(database: stack.database, secrets: stack.vault);
    // What this phone had before the restore: a subscription with a server,
    // a manual server, the installation id and some unrelated state.
    await stack.subscriptions.upsert(Fixtures.subscription());
    await stack.nodes.upsertAll(<ProxyNode>[
      Fixtures.vlessNode(subscriptionId: 'sub-1'),
      Fixtures.trojanNode(),
    ]);
    await stack.store.write(SecretKeys.deviceId, 'hwid-of-this-phone');
    await stack.settings.write(const AppSettings(autoConnect: true));
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftLibraryStore.replaceLibrary', () {
    test('what was there is gone and what arrived is there, secrets and all',
        () async {
      final restored = Fixtures.vlessNode(
        id: 'node-restored',
        subscriptionId: 'sub-new',
      );

      final result = await store.replaceLibrary(
        subscriptions: <Subscription>[newSubscription()],
        groups: const <NodeGroup>[],
        nodes: <ProxyNode>[restored, Fixtures.socksNode()],
      );

      expect(result.isOk, isTrue);
      final subscriptions = (await stack.subscriptions.getAll()).valueOrNull!;
      expect(subscriptions.map((s) => s.id), <String>['sub-new']);
      expect(subscriptions.single.url, newSubscriptionUrl);
      final nodes = (await stack.nodes.getAll()).valueOrNull!;
      expect(nodes.map((n) => n.id).toSet(), <String>{
        'node-restored',
        'node-socks',
      });
      final back = nodes.firstWhere((n) => n.id == 'node-restored');
      expect(back.param('uuid'), Fixtures.uuid);
      expect(back.param('sid'), Fixtures.shortId);
      expect(back.subscriptionId, 'sub-new');
    });

    test('the credentials of what was replaced leave the keystore', () async {
      await store.replaceLibrary(
        subscriptions: <Subscription>[newSubscription()],
        groups: const <NodeGroup>[],
        nodes: const <ProxyNode>[],
      );

      final keys = stack.store.snapshot.keys;
      expect(keys, isNot(contains(SecretKeys.nodeParams('node-vless'))));
      expect(keys, isNot(contains(SecretKeys.nodeParams('node-trojan'))));
      expect(keys, isNot(contains(SecretKeys.subscriptionUrl('sub-1'))));
      expect(keys, contains(SecretKeys.subscriptionUrl('sub-new')));
      // Nothing of the old secrets survives anywhere in the store.
      final values = stack.store.snapshot.values.join('\n');
      expect(values, isNot(contains(Fixtures.password)));
      expect(values, isNot(contains(Fixtures.uuid)));
    });

    test('the installation id and everything outside the library stay',
        () async {
      await store.replaceLibrary(
        subscriptions: const <Subscription>[],
        groups: const <NodeGroup>[],
        nodes: const <ProxyNode>[],
      );

      expect(stack.store.snapshot[SecretKeys.deviceId], 'hwid-of-this-phone');
      expect((await stack.settings.read()).valueOrNull!.autoConnect, isTrue);
    });

    test('restoring onto the same install — same ids — is not a conflict',
        () async {
      final result = await store.replaceLibrary(
        subscriptions: <Subscription>[Fixtures.subscription()],
        groups: const <NodeGroup>[],
        nodes: <ProxyNode>[Fixtures.vlessNode(subscriptionId: 'sub-1')],
      );

      expect(result.isOk, isTrue);
      final nodes = (await stack.nodes.getAll()).valueOrNull!;
      expect(nodes.map((n) => n.id), <String>['node-vless']);
      expect(nodes.single.param('uuid'), Fixtures.uuid);
    });

    test('groups come back with the servers in them', () async {
      const group = NodeGroup(id: 'group-1', name: 'Work');

      await store.replaceLibrary(
        subscriptions: const <Subscription>[],
        groups: const <NodeGroup>[group],
        nodes: <ProxyNode>[Fixtures.vlessNode(groupId: 'group-1')],
      );

      final groups = await stack.nodes.watchGroups().first;
      expect(groups.map((g) => g.id), <String>['group-1']);
      expect(
        (await stack.nodes.getAll()).valueOrNull!.single.groupId,
        'group-1',
      );
    });

    test('a keystore that refuses leaves the old library whole', () async {
      final failing = DriftLibraryStore(
        database: stack.database,
        secrets: SecretVault(store: InMemorySecureStore(failOnWrite: true)),
      );

      final result = await failing.replaceLibrary(
        subscriptions: <Subscription>[newSubscription()],
        groups: const <NodeGroup>[],
        nodes: const <ProxyNode>[],
      );

      expect(result.failureOrNull, isA<StorageFailure>());
      final subscriptions = (await stack.subscriptions.getAll()).valueOrNull!;
      expect(subscriptions.map((s) => s.id), <String>['sub-1']);
      final nodes = (await stack.nodes.getAll()).valueOrNull!;
      expect(
        nodes.map((n) => n.id).toSet(),
        <String>{'node-vless', 'node-trojan'},
      );
      expect(
        nodes.firstWhere((n) => n.id == 'node-vless').param('uuid'),
        Fixtures.uuid,
      );
    });

    test('a batch that fails gives the old library its own credentials back',
        () async {
      // The backup shares node-vless's id but carries other credentials, and
      // one of its servers names a subscription that is not there, so the
      // batch fails after the keystore was already written.
      final changed = Fixtures.vlessNode(subscriptionId: 'sub-1').copyWith(
        params: <String, Object?>{'uuid': 'other-uuid', 'security': 'none'},
      );

      final result = await store.replaceLibrary(
        subscriptions: <Subscription>[Fixtures.subscription()],
        groups: const <NodeGroup>[],
        nodes: <ProxyNode>[
          changed,
          Fixtures.socksNode(id: 'orphan').copyWith(subscriptionId: 'nowhere'),
        ],
      );

      expect(result.isErr, isTrue);
      final nodes = (await stack.nodes.getAll()).valueOrNull!;
      final vless = nodes.firstWhere((n) => n.id == 'node-vless');
      expect(vless.param('uuid'), Fixtures.uuid);
      expect(
        stack.store.snapshot.keys,
        isNot(contains(SecretKeys.nodeParams('orphan'))),
      );
    });

    test('readLibrary brings every credential back', () async {
      final library = (await store.readLibrary()).valueOrNull!;

      expect(library.subscriptions.single.url, Fixtures.subscriptionUrl);
      expect(
        library.nodes.firstWhere((n) => n.id == 'node-vless').param('uuid'),
        Fixtures.uuid,
      );
      expect(
        library.nodes
            .firstWhere((n) => n.id == 'node-trojan')
            .param('password'),
        Fixtures.password,
      );
    });

    test(
        'readLibrary fails when the keystore cannot be read, rather than '
        'answering without credentials', () async {
      final blind = DriftLibraryStore(
        database: stack.database,
        secrets: SecretVault(store: InMemorySecureStore(failOnRead: true)),
      );

      final result = await blind.readLibrary();

      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('a node naming a subscription that is not there fails as a whole',
        () async {
      // BackupSnapshot.fromJson never lets this through; if something else
      // did, the batch must fail whole rather than half-write.
      final result = await store.replaceLibrary(
        subscriptions: const <Subscription>[],
        groups: const <NodeGroup>[],
        nodes: <ProxyNode>[Fixtures.vlessNode(subscriptionId: 'nowhere')],
      );

      expect(result.isErr, isTrue);
      final nodes = (await stack.nodes.getAll()).valueOrNull!;
      expect(
        nodes.map((n) => n.id).toSet(),
        <String>{'node-vless', 'node-trojan'},
      );
    });
  });
}
