import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/node_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What the per-node menu asks the graph to do, without the widgets.
///
/// The two interesting cases are both about not leaving debris: a copy that
/// failed must not look like one that worked, and deleting the server the
/// tunnel is running through must take the tunnel down with it rather than
/// leave the core pointed at an outbound nothing can name any more.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  void start({List<ProxyNode> nodes = const <ProxyNode>[]}) {
    harness = CommyTestHarness(nodes: nodes);
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final subscriptions = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(selectedNodeIdProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });
  }

  NodeController controllerOf() =>
      container.read(nodeControllerProvider.notifier);

  /// Settles the stored selection, the way a screen that has been on display
  /// for a frame already has.
  Future<void> selectNode(String? id) async {
    await container.read(selectedNodeIdProvider.future);
    await container.read(selectedNodeIdProvider.notifier).select(id);
  }

  group('copyLink', () {
    test('puts the rendered link on the clipboard', () async {
      final node = testNode();
      start(nodes: <ProxyNode>[node]);

      final copied = await controllerOf().copyLink(node);

      expect(copied, isTrue);
      expect(harness.clipboard.text, startsWith('vless://'));
      expect(harness.clipboard.text, contains('nl-03.example.net:443'));
      expect(container.read(nodeControllerProvider).failure, isNull);
    });

    test('a node with no renderable link says so and copies nothing',
        () async {
      // WireGuard without a private key has no link form: the exporter
      // refuses rather than emitting something no other client can read.
      const node = ProxyNode(
        id: 'wg-1',
        name: 'Home',
        protocol: Protocol.wireguard,
        host: 'wg.example.net',
        port: 51820,
      );
      start(nodes: <ProxyNode>[node]);

      final copied = await controllerOf().copyLink(node);

      expect(copied, isFalse);
      expect(harness.clipboard.text, isNull);
      expect(
        container.read(nodeControllerProvider).failure,
        isA<ConfigInvalidFailure>(),
      );
    });
  });

  group('delete', () {
    test('removes the row and leaves an unrelated selection alone', () async {
      final kept = testNode(id: 'node-2', name: 'Warsaw 01');
      final doomed = testNode();
      start(nodes: <ProxyNode>[doomed, kept]);
      await selectNode(kept.id);

      await controllerOf().delete(doomed);

      expect(
        harness.nodeRepository.nodes.map((node) => node.id),
        <String>['node-2'],
      );
      expect(container.read(selectedNodeIdProvider).value, kept.id);
    });

    test('clears the selection when the deleted node was the chosen one',
        () async {
      final node = testNode();
      start(nodes: <ProxyNode>[node]);
      await selectNode(node.id);

      await controllerOf().delete(node);

      expect(harness.nodeRepository.nodes, isEmpty);
      expect(container.read(selectedNodeIdProvider).value, isNull);
      expect(harness.settingsRepository.selectedNodeId, isNull);
    });

    test('takes the tunnel down when it is running through the node',
        () async {
      final node = testNode();
      start(nodes: <ProxyNode>[node]);

      final started =
          await container.read(tunnelControllerProvider.notifier).connect(
                nodeId: node.id,
              );
      expect(started, isTrue);
      await harness.core.status
          .firstWhere((status) => status is TunnelConnected)
          .timeout(const Duration(seconds: 5));
      expect(controllerOf().isLive(node), isTrue);

      await controllerOf().delete(node);

      expect(harness.core.isRunning, isFalse);
      expect(harness.nodeRepository.nodes, isEmpty);
      expect(container.read(selectedNodeIdProvider).value, isNull);
    });
  });

  group('delete on Auto', () {
    // The stored selection is Amsterdam, the server the list leads with; the
    // core's Auto group is on Warsaw, and the traffic with it.
    final stored = testNode();
    final picked = testNode(id: 'node-2', name: 'Warsaw 01');
    final other = testNode(id: 'node-3', name: 'Oslo 01');

    Future<void> onAuto() async {
      final members = <String>[
        for (final node in <ProxyNode>[stored, picked, other])
          SingBoxTags.forNode(node),
      ];
      harness = CommyTestHarness(
        nodes: <ProxyNode>[stored, picked, other],
        settings: AppSettings.defaults.copyWith(autoSelect: true),
        coreGroups: <ProxyGroup>[
          ProxyGroup(
            tag: SingBoxTags.autoGroup,
            type: 'urltest',
            now: SingBoxTags.forNode(picked),
            all: members,
          ),
          ProxyGroup(
            tag: SingBoxTags.proxyGroup,
            type: 'selector',
            now: SingBoxTags.autoGroup,
            all: <String>[SingBoxTags.autoGroup, ...members],
          ),
        ],
      );
      container = ProviderContainer(overrides: harness.overrides());
      final subscriptions = <ProviderSubscription<Object?>>[
        container.listen(nodesProvider, (_, __) {}),
        container.listen(settingsProvider, (_, __) {}),
        container.listen(coreStatusProvider, (_, __) {}),
        container.listen(selectedNodeIdProvider, (_, __) {}),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          subscription.close();
        }
        container.dispose();
        await harness.dispose();
      });
      await container.read(nodesProvider.future);
      await container.read(settingsProvider.future);
      await container.read(selectedNodeIdProvider.future);

      final started = await container
          .read(tunnelControllerProvider.notifier)
          .connect(nodeId: stored.id);
      expect(started, isTrue);
      await harness.core.status
          .firstWhere((status) => status is TunnelConnected)
          .timeout(const Duration(seconds: 5));
      // Home's Auto row, which is what keeps the core's answer current.
      final home = container.listen(proxyGroupsProvider, (_, __) {});
      addTearDown(home.close);
      await container.read(proxyGroupsProvider.future);
      expect(container.read(autoNodeProvider)?.id, picked.id);
      expect(container.read(selectedNodeIdProvider).value, stored.id);
    }

    test('warns about the server Auto is on, not the stored one', () async {
      await onAuto();

      expect(controllerOf().isLive(picked), isTrue);
      expect(controllerOf().isLive(stored), isFalse);
    });

    test('the stored server goes without taking the tunnel down', () async {
      await onAuto();

      await controllerOf().delete(stored);

      expect(harness.core.isRunning, isTrue);
      expect(harness.core.stopCalls, 0);
      expect(
        harness.nodeRepository.nodes.map((node) => node.id),
        isNot(contains(stored.id)),
      );
      // Moved on, not emptied: a reload builds from it.
      expect(container.read(selectedNodeIdProvider).value, picked.id);
      expect(harness.settingsRepository.selectedNodeId, picked.id);
    });

    test('the server Auto is on takes the tunnel down with it', () async {
      await onAuto();

      await controllerOf().delete(picked);

      expect(harness.core.isRunning, isFalse);
      expect(
        harness.nodeRepository.nodes.map((node) => node.id),
        isNot(contains(picked.id)),
      );
      expect(container.read(selectedNodeIdProvider).value, stored.id);
    });
  });
}
