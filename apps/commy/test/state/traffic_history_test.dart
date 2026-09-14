import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The pump behind the daily totals.
///
/// It is watched from the root of the app, so what it does with the core's
/// samples has to be right without any screen open: every tick reaches the
/// store while the tunnel is up, and the baseline is dropped when it is not.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  setUp(() async {
    harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(trafficHistoryPumpProvider, (_, __) {}),
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
  });

  Future<TunnelStatus> waitFor(
    bool Function(TunnelStatus status) matches, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return harness.core.status.firstWhere(matches).timeout(timeout);
  }

  test('every sample reaches the store while the tunnel is up', () async {
    final tunnel = container.read(tunnelControllerProvider.notifier);
    expect(await tunnel.connect(nodeId: 'node-1'), isTrue);
    await waitFor((status) => status is TunnelConnected);

    // The fake core ticks every 50 ms; a few of them is enough to know the
    // samples are flowing rather than to count them.
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(harness.trafficHistory.recorded.length, greaterThanOrEqualTo(2));
    expect(
      harness.trafficHistory.recorded.last.uplinkTotal,
      greaterThanOrEqualTo(harness.trafficHistory.recorded.first.uplinkTotal),
    );
  });

  test('the baseline is dropped when the tunnel goes down', () async {
    final tunnel = container.read(tunnelControllerProvider.notifier);
    expect(await tunnel.connect(nodeId: 'node-1'), isTrue);
    await waitFor((status) => status is TunnelConnected);
    final before = harness.trafficHistory.resets;

    await tunnel.disconnect();
    await waitFor((status) => status is TunnelIdle);
    // The reset rides on the status listener, which fires a microtask later.
    await Future<void>.delayed(Duration.zero);

    expect(harness.trafficHistory.resets, greaterThan(before));
  });
}
