import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The whole of scenario 1 from docs/05-ux-flows.md, without a device.
///
/// Paste a link, it is parsed and stored, it is selected, the config is built
/// from it, the core is started, and the status stream walks to `connected`.
/// Every step below is the shipping code path — the same controllers, the same
/// use cases, the same builder — with only the repositories and the tunnel
/// swapped.
void main() {
  const link = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Amsterdam%2003';

  late CommyTestHarness harness;
  late ProviderContainer container;

  /// Stands the graph up. Called by each test so a test that needs a
  /// differently configured core can build its own before anything reads it.
  void start({CommyTestHarness? withHarness}) {
    harness = withHarness ?? CommyTestHarness();
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    // Keep the streams alive for the whole test: a provider nobody listens to
    // is disposed between reads, and the flow would restart on each one.
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

  Future<TunnelStatus> waitFor(
    bool Function(TunnelStatus status) matches, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return harness.core.status.firstWhere(matches).timeout(timeout);
  }

  test('paste, store, select, connect, and the core reports connected',
      () async {
    start();

    // 1. Import.
    final nodeId =
        await container.read(importControllerProvider.notifier).importText(
              link,
            );
    expect(nodeId, isNotNull);

    final importState = container.read(importControllerProvider);
    expect(importState.failure, isNull);
    expect(importState.outcome?.nodes, hasLength(1));

    // 2. It landed in the repository, with the credential separated out.
    final stored = harness.nodeRepository.nodes.single;
    expect(stored.name, 'Amsterdam 03');
    expect(stored.protocol, Protocol.vless);
    expect(stored.host, 'nl-03.example.net');
    expect(stored.port, 443);

    // 3. Connect through the real use case.
    final started =
        await container.read(tunnelControllerProvider.notifier).connect(
              nodeId: nodeId,
            );
    expect(started, isTrue);
    expect(container.read(tunnelControllerProvider).failure, isNull);

    // 4. The selection was written where the next cold start will find it.
    expect(harness.settingsRepository.selectedNodeId, nodeId);

    // 5. The core actually reaches connected, through starting.
    await waitFor((status) => status is TunnelStarting);
    await waitFor((status) => status is TunnelConnected);

    // 6. What was handed to the core is a real, complete document, and the
    //    diagnostics tab can show it.
    final config = container.read(tunnelControllerProvider).lastConfig;
    expect(config, isNotNull);
    expect(config!.document.keys, contains(SingBoxKeys.outbounds));
    expect(config.document.keys, contains(SingBoxKeys.inbounds));

    // 7. And the selector group is in it, which is what makes switching a
    //    `select()` rather than a restart.
    final outbounds = config.document[SingBoxKeys.outbounds]! as List<Object?>;
    final tags = <String>[
      for (final outbound in outbounds)
        (outbound! as Map<String, Object?>)[SingBoxKeys.tag]! as String,
    ];
    expect(tags, contains(SingBoxTags.proxyGroup));
    expect(tags, contains(SingBoxTags.forNode(stored)));

    await container.read(tunnelControllerProvider.notifier).disconnect();
    await waitFor((status) => status is TunnelIdle);
  });

  test('switching servers selects inside the running core, never restarts',
      () async {
    final first = testNode(id: 'node-a');
    final second = testNode(id: 'node-b', name: 'Poland 10gb per s');
    start(
      withHarness: CommyTestHarness(
        nodes: <ProxyNode>[first, second],
        // The fake rejects a tag that is not in the group, the way a real
        // core does, so the outbounds the switch will ask for are declared.
        coreGroups: <ProxyGroup>[
          ProxyGroup(
            tag: SingBoxTags.proxyGroup,
            type: 'selector',
            now: SingBoxTags.forNode(first),
            all: <String>[
              SingBoxTags.forNode(first),
              SingBoxTags.forNode(second),
            ],
          ),
        ],
      ),
    );

    await container.read(tunnelControllerProvider.notifier).connect(
          nodeId: first.id,
        );
    await waitFor((status) => status is TunnelConnected);

    // A restart would take the status back through idle. Watching for that is
    // the assertion: if it happens, this future completes and the test fails.
    var wentIdle = false;
    final watcher = harness.core.status.listen((status) {
      if (status is TunnelIdle || status is TunnelStopping) {
        wentIdle = true;
      }
    });
    addTearDown(() async => watcher.cancel());

    await container.read(tunnelControllerProvider.notifier).selectNode(second);

    expect(wentIdle, isFalse, reason: 'switching must not drop the tunnel');
    expect(harness.settingsRepository.selectedNodeId, second.id);
    expect(
      container.read(tunnelControllerProvider).notice?.kind,
      TunnelNoticeKind.switched,
    );

    await container.read(tunnelControllerProvider.notifier).disconnect();
    await waitFor((status) => status is TunnelIdle);
  });

  test('an import that parses nothing is an empty result, not a failure',
      () async {
    start();
    final nodeId = await container
        .read(importControllerProvider.notifier)
        .importText('this is not a link');

    expect(nodeId, isNull);
    final state = container.read(importControllerProvider);
    expect(state.outcome?.nodes ?? const <ProxyNode>[], isEmpty);
    expect(harness.nodeRepository.nodes, isEmpty);
  });

  test('connect with nothing selected asks the caller to import instead',
      () async {
    start();
    final started =
        await container.read(tunnelControllerProvider.notifier).connect();

    expect(started, isFalse);
    expect(container.read(tunnelControllerProvider).failure, isNull);
  });
}
