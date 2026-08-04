import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

void main() {
  late TestStack stack;
  late DriftNodeRepository repository;

  setUp(() async {
    stack = TestStack.create();
    repository = stack.nodes;
    // `NodeRows.subscriptionId` is a real foreign key and the database opens
    // with `PRAGMA foreign_keys = ON`, so a node cannot reference a
    // subscription that was never saved. Seeding both here mirrors the only
    // order that can happen in the app — the subscription is stored before its
    // nodes are — and without it every insert is rejected, the repository
    // returns an Err nobody looked at, and the table silently stays empty.
    await stack.subscriptions.upsert(Fixtures.subscription());
    await stack.subscriptions
        .upsert(Fixtures.subscription(id: 'sub-2', sortIndex: 1));
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftNodeRepository', () {
    test('a saved node comes back whole, credentials included', () async {
      final node = Fixtures.vlessNode();
      await repository.upsertAll(<ProxyNode>[node]);

      final loaded = (await repository.findById(node.id)).valueOrNull;

      expect(loaded, isNotNull);
      expect(loaded!.param('uuid'), equals(Fixtures.uuid));
      expect(loaded.param('sid'), equals(Fixtures.shortId));
      expect(loaded.param('sni'), equals('www.microsoft.com'));
      expect(loaded.protocol, equals(Protocol.vless));
      expect(loaded.port, equals(443));
    });

    test('findById returns null for an unknown id', () async {
      expect((await repository.findById('nope')).valueOrNull, isNull);
    });

    test('getAll orders by sortIndex', () async {
      await repository.upsertAll(<ProxyNode>[
        Fixtures.trojanNode(sortIndex: 1),
        Fixtures.vlessNode(),
      ]);

      final all = (await repository.getAll()).valueOrNull!;
      final ids = all.map((node) => node.id).toList();

      expect(ids, equals(<String>['node-vless', 'node-trojan']));
    });

    test('watchAll emits hydrated nodes', () async {
      await repository.upsertAll(<ProxyNode>[Fixtures.vlessNode()]);

      final emitted = await repository.watchAll().first;

      expect(emitted, hasLength(1));
      expect(emitted.single.param('uuid'), equals(Fixtures.uuid));
    });

    test('deleting a node removes its credentials too', () async {
      final node = Fixtures.vlessNode();
      await repository.upsertAll(<ProxyNode>[node]);
      await repository.deleteById(node.id);

      expect((await repository.getAll()).valueOrNull, isEmpty);
      expect(
        stack.store.snapshot.containsKey(SecretKeys.nodeParams(node.id)),
        isFalse,
      );
    });

    test('updateLatency stores the measurement', () async {
      final node = Fixtures.vlessNode();
      final at = DateTime.utc(2026, 8, 4, 10);
      await repository.upsertAll(<ProxyNode>[node]);
      await repository.updateLatency(
        id: node.id,
        latency: const Duration(milliseconds: 148),
        checkedAt: at,
      );

      final loaded = (await repository.findById(node.id)).valueOrNull!;

      expect(loaded.latency, equals(const Duration(milliseconds: 148)));
      expect(loaded.lastCheckedAt, equals(at));
    });

    test('updateLatency with null records a timeout', () async {
      final node = Fixtures.vlessNode();
      await repository.upsertAll(<ProxyNode>[node]);
      await repository.updateLatency(
        id: node.id,
        latency: null,
        checkedAt: DateTime.utc(2026, 8, 4, 10),
      );

      expect((await repository.findById(node.id)).valueOrNull!.latency, isNull);
    });

    test('reorder rewrites the display order', () async {
      await repository.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(),
        Fixtures.trojanNode(sortIndex: 1),
      ]);
      await repository.reorder(<String>['node-trojan', 'node-vless']);

      final all = (await repository.getAll()).valueOrNull!;

      expect(all.first.id, equals('node-trojan'));
    });

    test('deleteBySubscription clears rows and credentials', () async {
      await repository.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(subscriptionId: 'sub-1'),
        Fixtures.trojanNode(subscriptionId: 'sub-1', sortIndex: 1),
        Fixtures.socksNode(),
      ]);
      await repository.deleteBySubscription('sub-1');

      final remaining = (await repository.getAll()).valueOrNull!;

      expect(
        remaining.map((node) => node.id).toList(),
        equals(<String>[
          'node-socks',
        ]),
      );
      expect(
        stack.store.snapshot.keys.where(
          (key) => key.startsWith(SecretKeys.nodePrefix),
        ),
        isEmpty,
      );
    });

    test('a keystore that refuses to write fails the save', () async {
      final broken = TestStack.create(
        store: InMemorySecureStore(failOnWrite: true),
      );
      addTearDown(broken.dispose);

      final result =
          await broken.nodes.upsertAll(<ProxyNode>[Fixtures.vlessNode()]);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<StorageFailure>());
      expect((await broken.nodes.getAll()).valueOrNull, isEmpty);
    });
  });

  group('DriftNodeRepository.replaceForSubscription', () {
    test('keeps the id and latency of a server that did not move', () async {
      const subscriptionId = 'sub-1';
      final original = Fixtures.vlessNode(
        id: 'local-id',
        subscriptionId: subscriptionId,
      );
      await repository.upsertAll(<ProxyNode>[original]);
      await repository.updateLatency(
        id: 'local-id',
        latency: const Duration(milliseconds: 90),
        checkedAt: DateTime.utc(2026, 8, 4),
      );

      // The panel renamed the node and handed us a fresh id.
      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.vlessNode(
            id: 'panel-generated-id',
            subscriptionId: subscriptionId,
          ).copyWith(name: 'Frankfurt Reality v2'),
        ],
      );

      final all = (await repository.getAll()).valueOrNull!;

      expect(all, hasLength(1));
      expect(all.single.id, equals('local-id'));
      expect(all.single.name, equals('Frankfurt Reality v2'));
      expect(all.single.latency, equals(const Duration(milliseconds: 90)));
    });

    test('drops servers the panel removed, with their credentials', () async {
      const subscriptionId = 'sub-1';
      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.vlessNode(subscriptionId: subscriptionId),
          Fixtures.trojanNode(subscriptionId: subscriptionId, sortIndex: 1),
        ],
      );
      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[Fixtures.vlessNode(subscriptionId: subscriptionId)],
      );

      final all = (await repository.getAll()).valueOrNull!;

      expect(
        all.map((node) => node.id).toList(),
        equals(<String>[
          'node-vless',
        ]),
      );
      expect(
        stack.store.snapshot.containsKey(
          SecretKeys.nodeParams('node-trojan'),
        ),
        isFalse,
      );
    });

    test('renumbers sortIndex from the order the panel gave', () async {
      const subscriptionId = 'sub-1';
      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.trojanNode(subscriptionId: subscriptionId, sortIndex: 99),
          Fixtures.vlessNode(subscriptionId: subscriptionId, sortIndex: 99),
        ],
      );

      final all = (await repository.getAll()).valueOrNull!;

      expect(all.map((node) => node.sortIndex).toList(), equals(<int>[0, 1]));
      expect(all.first.id, equals('node-trojan'));
    });

    test('leaves nodes of another subscription alone', () async {
      await repository.upsertAll(<ProxyNode>[
        Fixtures.socksNode(),
        Fixtures.trojanNode(subscriptionId: 'sub-2'),
      ]);
      await repository.replaceForSubscription(
        subscriptionId: 'sub-1',
        nodes: <ProxyNode>[Fixtures.vlessNode(subscriptionId: 'sub-1')],
      );

      final all = (await repository.getAll()).valueOrNull!;
      final ids = all.map((node) => node.id).toList();

      expect(ids, containsAll(<String>['node-socks', 'node-trojan']));
    });
  });

  group('DriftNodeRepository groups', () {
    test('a group round trips', () async {
      final group = NodeGroup(
        id: 'group-1',
        name: 'Imported by hand',
        createdAt: DateTime.utc(2026, 8, 4),
      );
      await repository.upsertGroup(group);

      final groups = await repository.watchGroups().first;

      expect(groups, hasLength(1));
      expect(groups.single.name, equals('Imported by hand'));
    });

    test('deleting a group takes its nodes and their credentials', () async {
      await repository.upsertGroup(
        const NodeGroup(id: 'group-1', name: 'Manual'),
      );
      await repository.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(groupId: 'group-1'),
      ]);

      await repository.deleteGroup('group-1');

      expect((await repository.getAll()).valueOrNull, isEmpty);
      expect(
        stack.store.snapshot.containsKey(
          SecretKeys.nodeParams('node-vless'),
        ),
        isFalse,
      );
    });
  });
}
