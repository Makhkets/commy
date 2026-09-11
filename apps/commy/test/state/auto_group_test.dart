import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #14: the Auto group, from the setting to the running core.
///
/// The builder has emitted a `urltest` group since the first milestone and
/// nothing ever asked for one, so the feature existed only in
/// `sing_box_config_builder_test.dart`. These tests follow the whole path the
/// user's tap takes: the setting, the document, and what the running core is
/// asked to do about it.
///
/// The one thing worth stating up front, because every case below turns on it:
/// **Auto lives in the document.** A core started without it has no such
/// outbound, so turning Auto on has to rebuild — and a core that already has
/// the group only needs the selector pointed at it, which costs nothing and
/// drops no connections.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  Future<void> start({
    required List<ProxyNode> nodes,
    bool autoSelect = false,
  }) async {
    harness = CommyTestHarness(
      nodes: nodes,
      settings: AppSettings.defaults.copyWith(autoSelect: autoSelect),
    );
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(selectedNodeIdProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    await container.read(nodesProvider.future);
    await container.read(settingsProvider.future);
    await container.read(selectedNodeIdProvider.future);
  }

  TunnelController tunnel() =>
      container.read(tunnelControllerProvider.notifier);

  /// Brings the tunnel up and waits for the core to say so.
  Future<void> connect({String? nodeId}) async {
    expect(await tunnel().connect(nodeId: nodeId), isTrue);
    await harness.core.status
        .firstWhere((status) => status is TunnelConnected)
        .timeout(const Duration(seconds: 5));
  }

  /// The document the generator produces for [settings], as text.
  String documentFor(AppSettings settings) {
    final built = container.read(configGeneratorProvider).build(
          node: testNode(),
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: settings,
          includeClashApi: false,
        );
    return built.valueOrNull!.encode();
  }

  Future<bool> storedAutoSelect() async {
    final settings = await harness.settingsRepository.read();
    return settings.valueOrNull!.autoSelect;
  }

  /// The polled view of the groups, once it has answered.
  ///
  /// Listened to before it is awaited on purpose: a bare `read` of `.future`
  /// subscribes and unsubscribes in the same breath, and a stream that has not
  /// answered yet then never gets the chance.
  Future<List<ProxyGroup>> reportedGroups() async {
    final handle = container.listen(proxyGroupsProvider, (_, __) {});
    addTearDown(handle.close);
    return container.read(proxyGroupsProvider.future);
  }

  Future<ProxyGroup?> groupNamed(String tag) async {
    for (final group in await harness.core.proxies()) {
      if (group.tag == tag) {
        return group;
      }
    }
    return null;
  }

  group('the document', () {
    test('carries the group and defaults to it when Auto is on', () async {
      await start(
        nodes: <ProxyNode>[testNode(), testNode(id: 'node-2', name: 'Warsaw')],
      );

      final document = documentFor(
        AppSettings.defaults.copyWith(autoSelect: true),
      );

      expect(document, contains('"tag":"auto"'));
      expect(document, contains('"type":"urltest"'));
      expect(document, contains('"default":"auto"'));
    });

    test('leaves the group out while Auto is off', () async {
      await start(
        nodes: <ProxyNode>[testNode(), testNode(id: 'node-2', name: 'Warsaw')],
      );

      expect(
        documentFor(AppSettings.defaults),
        isNot(contains('"tag":"auto"')),
      );
    });

    test('leaves it out for a single server, asked for or not', () async {
      // A group of one measures a server against itself. The builder knows
      // this; the screen asks the builder rather than deciding again.
      await start(nodes: <ProxyNode>[testNode()]);

      final document = documentFor(
        AppSettings.defaults.copyWith(autoSelect: true),
      );

      expect(document, isNot(contains('"tag":"auto"')));
      expect(container.read(autoSelectedProvider), isFalse);
    });
  });

  group('choosing Auto', () {
    test('with the tunnel down it only writes the setting', () async {
      await start(
        nodes: <ProxyNode>[testNode(), testNode(id: 'node-2', name: 'Warsaw')],
      );

      await tunnel().selectAuto();

      expect(await storedAutoSelect(), isTrue);
      expect(harness.core.startCalls, 0);
      expect(harness.core.reloadCalls, 0);
    });

    test('rebuilds the running core when it has no such group', () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes);
      await connect(nodeId: nodes.first.id);
      expect(await groupNamed('auto'), isNull);

      await tunnel().selectAuto();

      expect(harness.core.reloadCalls, 1);
      expect(harness.core.lastConfig!.encode(), contains('"tag":"auto"'));
      expect((await groupNamed('proxy'))!.now, 'auto');
    });

    test('coming back to it inside one session is a switch, not a restart',
        () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes, autoSelect: true);
      await connect(nodeId: nodes.first.id);
      expect(await groupNamed('auto'), isNotNull);

      // Away to a server and back again. Neither step may rebuild: the
      // document already holds every member and the group itself.
      await tunnel().selectNode(nodes[1]);
      await tunnel().selectAuto();

      expect(harness.core.reloadCalls, 0);
      expect(harness.core.startCalls, 1);
      expect(await storedAutoSelect(), isTrue);
      expect((await groupNamed('proxy'))!.now, 'auto');
    });

    test('a start on Auto needs no server to have been picked first', () async {
      // Nothing was ever selected, which before this would leave the connect
      // button doing nothing at all.
      await start(
        nodes: <ProxyNode>[testNode(), testNode(id: 'node-2', name: 'Warsaw')],
        autoSelect: true,
      );
      expect(container.read(selectedNodeIdProvider).value, isNull);

      await connect();

      expect(harness.core.lastConfig!.encode(), contains('"default":"auto"'));
    });
  });

  group('choosing a server by hand', () {
    test('turns Auto off without restarting the core', () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes, autoSelect: true);
      await connect(nodeId: nodes.first.id);

      await tunnel().selectNode(nodes[1]);

      expect(await storedAutoSelect(), isFalse);
      expect(harness.core.reloadCalls, 0);
      expect((await groupNamed('proxy'))!.now, 'node-node-2');
      expect(container.read(selectedNodeIdProvider).value, 'node-2');
    });

    test('a switch that failed leaves Auto exactly as it was', () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes, autoSelect: true);
      await connect(nodeId: nodes.first.id);
      harness.core.failOn(
        FakeCoreStep.select,
        const CoreCrashedFailure('no'),
      );

      await tunnel().selectNode(nodes[1]);

      // Nothing moved, so nothing is claimed to have moved.
      expect(await storedAutoSelect(), isTrue);
      expect((await groupNamed('proxy'))!.now, 'auto');
      expect(container.read(tunnelControllerProvider).failure, isNotNull);
    });

    test('with the tunnel down it still ends Auto', () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes, autoSelect: true);

      await tunnel().selectNode(nodes[1]);

      expect(await storedAutoSelect(), isFalse);
      expect(container.read(selectedNodeIdProvider).value, 'node-2');
    });
  });

  group('what the core reports', () {
    test('names the server the group landed on', () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes, autoSelect: true);
      await connect(nodeId: nodes.first.id);

      await reportedGroups();

      expect(container.read(autoNodeProvider)?.id, nodes.first.id);
    });

    test("asks nothing at all while the server is the user's own choice",
        () async {
      final nodes = <ProxyNode>[
        testNode(),
        testNode(id: 'node-2', name: 'Warsaw'),
      ];
      await start(nodes: nodes);
      await connect(nodeId: nodes.first.id);

      expect(await reportedGroups(), isEmpty);
      expect(container.read(autoNodeProvider), isNull);
    });
  });
}
