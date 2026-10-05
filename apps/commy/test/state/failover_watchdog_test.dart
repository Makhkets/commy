import 'package:commy/src/state/failover_watchdog.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Failover: the chosen server stops answering, and the traffic moves to the
/// fastest live one — inside the running core, without a restart.
void main() {
  final chosen = testNode(id: 'node-a', subscriptionId: 'sub-1');
  final sibling = testNode(
    id: 'node-b',
    name: 'Frankfurt 01',
    subscriptionId: 'sub-1',
    latency: const Duration(milliseconds: 90),
  );
  final stranger = testNode(
    id: 'node-c',
    name: 'Warsaw 10',
    subscriptionId: 'sub-2',
    latency: const Duration(milliseconds: 20),
  );

  late CommyTestHarness harness;
  late ProviderContainer container;

  Future<FailoverWatchdog> connect({
    bool failover = true,
    bool autoSelect = false,
  }) async {
    harness = CommyTestHarness(
      nodes: <ProxyNode>[chosen, sibling, stranger],
      coreGroups: <ProxyGroup>[
        ProxyGroup(
          tag: SingBoxTags.proxyGroup,
          type: 'selector',
          now: SingBoxTags.forNode(chosen),
          all: <String>[
            for (final node in <ProxyNode>[chosen, sibling, stranger])
              SingBoxTags.forNode(node),
          ],
        ),
      ],
    );
    await harness.settingsRepository.write(
      AppSettings(failover: failover, autoSelect: autoSelect),
    );
    container = ProviderContainer(
      overrides: <Override>[
        ...harness.overrides(),
        // Never fires by itself: the tests call check() one at a time.
        failoverIntervalProvider.overrideWithValue(const Duration(hours: 1)),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    for (final provider in <ProviderListenable<Object?>>[
      nodesProvider,
      coreStatusProvider,
      selectedNodeIdProvider,
      settingsProvider,
    ]) {
      container.listen(provider, (_, __) {});
    }
    final watchdog = container.read(failoverWatchdogProvider);
    await container
        .read(tunnelControllerProvider.notifier)
        .connect(nodeId: chosen.id);
    await harness.core.status
        .firstWhere((status) => status is TunnelConnected)
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    return watchdog;
  }

  test('a dead server is left after two misses, for the fastest live one',
      () async {
    final watchdog = await connect();
    expect(watchdog.isWatching, isTrue);
    const quick = Duration(milliseconds: 30);
    const slower = Duration(milliseconds: 80);
    harness.core
      ..setLatency(SingBoxTags.forNode(chosen), null)
      ..setLatency(SingBoxTags.forNode(sibling), slower)
      ..setLatency(SingBoxTags.forNode(stranger), quick);
    var restarted = false;
    harness.core.status.listen((status) {
      if (status is TunnelIdle || status is TunnelStopping) {
        restarted = true;
      }
    });

    await watchdog.check();
    // One miss is a hiccup.
    expect(harness.settingsRepository.selectedNodeId, chosen.id);
    await watchdog.check();

    expect(harness.settingsRepository.selectedNodeId, stranger.id);
    expect(restarted, isFalse);
    final notice = container.read(tunnelControllerProvider).notice;
    expect(notice?.kind, TunnelNoticeKind.failedOver);
  });

  test('a server that answers is never moved off', () async {
    final watchdog = await connect();
    harness.core.setLatency(
      SingBoxTags.forNode(chosen),
      const Duration(milliseconds: 300),
    );

    await watchdog.check();
    await watchdog.check();
    await watchdog.check();

    expect(harness.settingsRepository.selectedNodeId, chosen.id);
  });

  test('when nothing answers, it is the network: nothing moves', () async {
    final watchdog = await connect();
    for (final node in <ProxyNode>[chosen, sibling, stranger]) {
      harness.core.setLatency(SingBoxTags.forNode(node), null);
    }

    await watchdog.check();
    await watchdog.check();

    expect(harness.settingsRepository.selectedNodeId, chosen.id);
  });

  test('off, or with Auto choosing, it does not watch at all', () async {
    expect((await connect(failover: false)).isWatching, isFalse);
  });

  test('Auto already keeps traffic on a live server', () async {
    expect((await connect(autoSelect: true)).isWatching, isFalse);
  });
}
