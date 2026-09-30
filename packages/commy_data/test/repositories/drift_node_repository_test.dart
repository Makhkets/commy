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

    group('several servers on one endpoint', () {
      // host:443 with a WebSocket path per server is an ordinary panel
      // layout. Ids come from the server's identity, path included, so the
      // two are two ids on one endpoint — and matching on the endpoint alone
      // gave one of them the other's id, collapsed the two rows into one and
      // deleted the other server's credentials.
      const subscriptionId = 'sub-1';

      ProxyNode onPath(String path) => ProxyNode(
            id: 'ws$path',
            name: 'Frankfurt $path',
            protocol: Protocol.vless,
            host: 'cdn.vpn.example.com',
            port: 443,
            subscriptionId: subscriptionId,
            params: <String, Object?>{
              'uuid': 'uuid-of$path',
              'type': 'ws',
              'path': path,
              'security': 'tls',
            },
          );

      Future<Map<String, ProxyNode>> stored() async => <String, ProxyNode>{
            for (final node in (await repository.getAll()).valueOrNull!)
              node.id: node,
          };

      test('a reordered pair keeps both servers, each with its own id',
          () async {
        await repository.replaceForSubscription(
          subscriptionId: subscriptionId,
          nodes: <ProxyNode>[onPath('/a'), onPath('/b')],
        );
        await repository.updateLatency(
          id: 'ws/a',
          latency: const Duration(milliseconds: 40),
          checkedAt: DateTime.utc(2026, 9, 30),
        );

        await repository.replaceForSubscription(
          subscriptionId: subscriptionId,
          nodes: <ProxyNode>[onPath('/b'), onPath('/a')],
        );

        final nodes = await stored();
        expect(nodes.keys.toSet(), <String>{'ws/a', 'ws/b'});
        expect(nodes['ws/a']!.param('path'), '/a');
        expect(nodes['ws/a']!.param('uuid'), 'uuid-of/a');
        expect(nodes['ws/b']!.param('uuid'), 'uuid-of/b');
        expect(nodes['ws/a']!.latency, const Duration(milliseconds: 40));
        expect(nodes['ws/b']!.latency, isNull);
      });

      test('a new server in front does not take the first one over', () async {
        await repository.replaceForSubscription(
          subscriptionId: subscriptionId,
          nodes: <ProxyNode>[onPath('/a')],
        );
        await repository.updateLatency(
          id: 'ws/a',
          latency: const Duration(milliseconds: 40),
          checkedAt: DateTime.utc(2026, 9, 30),
        );

        await repository.replaceForSubscription(
          subscriptionId: subscriptionId,
          nodes: <ProxyNode>[onPath('/new'), onPath('/a')],
        );

        final nodes = await stored();
        expect(nodes.keys.toSet(), <String>{'ws/new', 'ws/a'});
        expect(nodes['ws/a']!.latency, const Duration(milliseconds: 40));
        expect(nodes['ws/new']!.param('uuid'), 'uuid-of/new');
        expect(
          stack.store.snapshot.containsKey(SecretKeys.nodeParams('ws/a')),
          isTrue,
        );
      });
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

    test('a server the panel listed twice is stored once', () async {
      // An ordinary panel layout: one endpoint in two of its groups. A node's
      // identity leaves the display name out on purpose, so both entries
      // arrive under one id — and the refresh must survive that instead of
      // failing the whole subscription on a UNIQUE constraint.
      const subscriptionId = 'sub-1';

      final result = await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.vlessNode(subscriptionId: subscriptionId),
          Fixtures.vlessNode(subscriptionId: subscriptionId, sortIndex: 1)
              .copyWith(name: 'Frankfurt (Games)'),
        ],
      );

      final all = (await repository.getAll()).valueOrNull!;

      expect(result.isOk, isTrue);
      expect(all, hasLength(1));
      // The last entry wins the fields, which is where storing the two of them
      // one after another would have landed.
      expect(all.single.name, equals('Frankfurt (Games)'));
      // R2: the row that survived kept its credentials.
      expect(all.single.param('uuid'), equals(Fixtures.uuid));
    });

    test('a notice of two lines keeps both lines, refresh after refresh',
        () async {
      // A panel with two lines to say sends two entries at the same nowhere
      // address under one placeholder credential: one id, two texts. Folded
      // by id, only the last line — "Contact support" — was ever stored.
      const subscriptionId = 'sub-1';
      ProxyNode line(String text) => ProxyNode(
            id: 'stub',
            name: text,
            protocol: Protocol.vless,
            host: '0.0.0.0',
            port: 1,
            subscriptionId: subscriptionId,
            params: const <String, Object?>{
              'uuid': '00000000-0000-0000-0000-000000000000',
            },
          );
      Future<List<String>> messages() async => PanelNotice.messages(
            (await repository.findBySubscription(subscriptionId)).valueOrNull!,
          );

      for (var refresh = 0; refresh < 2; refresh++) {
        final result = await repository.replaceForSubscription(
          subscriptionId: subscriptionId,
          nodes: <ProxyNode>[
            line('Subscription expired'),
            line('Contact support'),
          ],
        );
        expect(result.isOk, isTrue);
        expect(
          await messages(),
          <String>['Subscription expired', 'Contact support'],
        );
      }

      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[line('Device limit reached'), line('Contact us')],
      );

      expect(await messages(), <String>['Device limit reached', 'Contact us']);
    });

    test('a repeated server leaves no hole in the display order', () async {
      const subscriptionId = 'sub-1';

      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.vlessNode(subscriptionId: subscriptionId),
          Fixtures.trojanNode(subscriptionId: subscriptionId, sortIndex: 1),
          Fixtures.vlessNode(subscriptionId: subscriptionId, sortIndex: 2)
              .copyWith(name: 'Frankfurt (Games)'),
        ],
      );

      final all = (await repository.getAll()).valueOrNull!;

      // The survivor keeps the first entry's place, so a repeat further down
      // the list neither moves Amsterdam nor leaves a gap behind it.
      expect(
        all.map((node) => node.id).toList(),
        equals(<String>['node-vless', 'node-trojan']),
      );
      expect(all.map((node) => node.sortIndex).toList(), equals(<int>[0, 1]));
    });

    test('a repeated server still carries the local id and its latency',
        () async {
      const subscriptionId = 'sub-1';
      await repository.upsertAll(<ProxyNode>[
        Fixtures.vlessNode(id: 'local-id', subscriptionId: subscriptionId),
      ]);
      await repository.updateLatency(
        id: 'local-id',
        latency: const Duration(milliseconds: 90),
        checkedAt: DateTime.utc(2026, 8, 4),
      );

      await repository.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: <ProxyNode>[
          Fixtures.vlessNode(id: 'panel-id', subscriptionId: subscriptionId),
          Fixtures.vlessNode(
            id: 'panel-id',
            subscriptionId: subscriptionId,
            sortIndex: 1,
          ).copyWith(name: 'Frankfurt (Games)'),
        ],
      );

      final all = (await repository.getAll()).valueOrNull!;

      expect(all, hasLength(1));
      expect(all.single.id, equals('local-id'));
      expect(all.single.latency, equals(const Duration(milliseconds: 90)));
      expect(all.single.param('uuid'), equals(Fixtures.uuid));
      // R2 from the other side: the keystore holds the row that survived and
      // nothing under the id the panel made up.
      expect(
        stack.store.snapshot.keys
            .where((key) => key.startsWith(SecretKeys.nodePrefix))
            .toList(),
        equals(<String>[SecretKeys.nodeParams('local-id')]),
      );
    });

    group('one server, two owners', () {
      // A node's id is its server and nothing else, so the same server under
      // two owners is the same id. The write used to take the other owner's
      // row over: a server pasted by hand became the subscription's and went
      // when the subscription was deleted, and two subscriptions of one
      // account emptied each other on every refresh.
      ProxyNode server({String? subscriptionId}) =>
          Fixtures.vlessNode(subscriptionId: subscriptionId);
      final heldBySub1 = DriftNodeRepository.ownedId('node-vless', 'sub-1');
      final heldBySub2 = DriftNodeRepository.ownedId('node-vless', 'sub-2');
      final heldByHand = DriftNodeRepository.ownedId('node-vless', null);

      Future<Map<String, String?>> owners() async => <String, String?>{
            for (final node in (await repository.getAll()).valueOrNull!)
              node.id: node.subscriptionId,
          };

      test('a subscription does not take a server pasted by hand', () async {
        await repository.upsertAll(<ProxyNode>[server()]);

        await repository.replaceForSubscription(
          subscriptionId: 'sub-1',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-1')],
        );

        expect(await owners(), <String, String?>{
          'node-vless': null,
          heldBySub1: 'sub-1',
        });
      });

      test('deleting that subscription leaves the pasted server whole',
          () async {
        await repository.upsertAll(<ProxyNode>[server()]);
        await repository.replaceForSubscription(
          subscriptionId: 'sub-1',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-1')],
        );

        await stack.subscriptions.deleteById('sub-1');

        final left = (await repository.getAll()).valueOrNull!;
        expect(left.map((node) => node.id), <String>['node-vless']);
        expect(left.single.param('uuid'), Fixtures.uuid);
      });

      test('two subscriptions listing one server keep a copy each', () async {
        for (final subscriptionId in <String>['sub-1', 'sub-2', 'sub-1']) {
          await repository.replaceForSubscription(
            subscriptionId: subscriptionId,
            nodes: <ProxyNode>[server(subscriptionId: subscriptionId)],
          );
        }

        expect(await owners(), <String, String?>{
          'node-vless': 'sub-1',
          heldBySub2: 'sub-2',
        });
        for (final subscriptionId in <String>['sub-1', 'sub-2']) {
          final nodes =
              (await repository.findBySubscription(subscriptionId)).valueOrNull;
          expect(nodes, hasLength(1), reason: subscriptionId);
          expect(nodes!.single.param('uuid'), Fixtures.uuid);
        }
      });

      test('the copy that stepped aside keeps its id and its latency',
          () async {
        await repository.replaceForSubscription(
          subscriptionId: 'sub-1',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-1')],
        );
        await repository.replaceForSubscription(
          subscriptionId: 'sub-2',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-2')],
        );
        await repository.updateLatency(
          id: heldBySub2,
          latency: const Duration(milliseconds: 70),
          checkedAt: DateTime.utc(2026, 9, 30),
        );
        // The first owner goes; the second one's copy is no longer in the
        // way of anything, and still must not move.
        await stack.subscriptions.deleteById('sub-1');

        await repository.replaceForSubscription(
          subscriptionId: 'sub-2',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-2')],
        );

        final left = (await repository.getAll()).valueOrNull!;
        expect(left.map((node) => node.id), <String>[heldBySub2]);
        expect(left.single.latency, const Duration(milliseconds: 70));
      });

      test("a paste does not take a subscription's server off its card",
          () async {
        await repository.replaceForSubscription(
          subscriptionId: 'sub-1',
          nodes: <ProxyNode>[server(subscriptionId: 'sub-1')],
        );

        await repository.upsertAll(<ProxyNode>[server()]);
        // Pasted again: it lands on the copy it made the first time.
        await repository.upsertAll(<ProxyNode>[server()]);

        expect(await owners(), <String, String?>{
          'node-vless': 'sub-1',
          heldByHand: null,
        });
      });
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
