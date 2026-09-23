import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #7: «Замерить все» ran one probe at a time, reported nothing
/// and could not be stopped. And the owner's "Ping" setting (2026-09-23): a
/// GET through the server by default, TCP or ICMP by choice — whether or not
/// the tunnel is up.
///
/// The progress is not a detail that can be taken on trust — it is what the
/// user watches — so the test follows the counter and asserts the steps it
/// moves in.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  List<ProxyNode> manyNodes(int count) => <ProxyNode>[
        for (var index = 0; index < count; index++)
          testNode(id: 'node-$index', name: 'Server $index', latency: null),
      ];

  ProxyNode udpNode() => const ProxyNode(
        id: 'node-udp',
        name: 'Hysteria',
        protocol: Protocol.hysteria2,
        host: 'hy.example.net',
        port: 8443,
      );

  Future<void> start(
    List<ProxyNode> nodes, {
    bool connect = false,
    PingMethod method = PingMethod.get,
  }) async {
    harness = CommyTestHarness(
      nodes: nodes,
      settings: AppSettings(pingMethod: method),
    );
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    await container.read(nodesProvider.future);
    await container.read(settingsProvider.future);
    if (connect) {
      await container.read(tunnelControllerProvider.notifier).connect(
            nodeId: nodes.first.id,
          );
      await harness.core.status
          .firstWhere((status) => status is TunnelConnected)
          .timeout(const Duration(seconds: 5));
    }
  }

  MeasurementController controller() =>
      container.read(measurementProvider.notifier);

  /// Every `done` the counter passed through, in order.
  List<int> watchProgress() {
    final steps = <int>[];
    final handle = container.listen<MeasurementState>(
      measurementProvider,
      (previous, next) {
        if (next.isRunning) {
          steps.add(next.done);
        }
      },
    );
    addTearDown(handle.close);
    return steps;
  }

  test('the counter moves one server at a time, several in flight', () async {
    final nodes = manyNodes(10);
    await start(nodes);
    final steps = watchProgress();

    await controller().measureAll(nodes, scopeId: 'sub-1');

    // 0 when the run is announced, then every server as it comes back: a
    // slow one holds its own slot, not a whole batch.
    expect(steps, <int>[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(MeasurementController.inFlight, 6);
  });

  test('every node ends up with a measurement, and the run ends idle',
      () async {
    final nodes = manyNodes(6);
    await start(nodes);

    await controller().measureAll(nodes, scopeId: 'sub-1');

    expect(container.read(measurementProvider).isRunning, isFalse);
    expect(
      harness.nodeRepository.nodes.every((node) => node.latency != null),
      isTrue,
    );
  });

  test('cancelling starts nothing more and leaves the rest unmeasured',
      () async {
    final nodes = manyNodes(12);
    await start(nodes);
    final handle = container.listen<MeasurementState>(
      measurementProvider,
      (previous, next) {
        if (next.done == 4) {
          container.read(measurementProvider.notifier).cancel();
        }
      },
    );
    addTearDown(handle.close);

    await controller().measureAll(nodes, scopeId: 'sub-1');

    final state = container.read(measurementProvider);
    expect(state.isRunning, isFalse);
    // What was already in flight is kept — a measurement that came back is
    // still true — but nothing after the cancel was started.
    expect(
      harness.core.probeCalls,
      lessThanOrEqualTo(4 + MeasurementController.inFlight),
    );
    final measured = harness.nodeRepository.nodes
        .where((node) => node.latency != null)
        .length;
    expect(measured, lessThan(nodes.length));
  });

  test('a second run while one is going is ignored', () async {
    final nodes = manyNodes(8);
    await start(nodes);
    final scopes = <String>{};
    final handle = container.listen<MeasurementState>(
      measurementProvider,
      (previous, next) {
        final scope = next.scopeId;
        if (scope != null) {
          scopes.add(scope);
        }
      },
    );
    addTearDown(handle.close);

    final first = controller().measureAll(nodes, scopeId: 'sub-1');
    await controller().measureAll(nodes, scopeId: 'sub-2');
    await first;

    // The second card never took the progress over: two runs sharing one
    // counter would give both of them a number that means nothing.
    expect(scopes, <String>{'sub-1'});
  });

  test('an empty list is not a run', () async {
    await start(manyNodes(1));

    await controller().measureAll(const <ProxyNode>[], scopeId: 'sub-1');

    expect(container.read(measurementProvider), MeasurementState.idle);
  });

  /// The header's ping button once failed on every press while the tunnel
  /// was down, and then measured only TCP handshakes until the user
  /// connected. A GET through the server is the number that says whether it
  /// works, and it is wanted before choosing one.
  group('GET, the default', () {
    test('goes through a probe core with the tunnel down', () async {
      final nodes = manyNodes(5);
      await start(nodes);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.core.probeCalls, 5);
      expect(harness.latencyProbe.asked, isEmpty);
      expect(
        harness.nodeRepository.nodes.map((node) => node.latency),
        everyElement(const Duration(milliseconds: 137)),
      );
      final state = container.read(measurementProvider);
      expect(state.isRunning, isFalse);
      expect(state.failure, isNull);
    });

    test('and the same way with the tunnel up', () async {
      final nodes = manyNodes(3);
      await start(nodes, connect: true);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.core.probeCalls, 3);
      expect(harness.latencyProbe.asked, isEmpty);
    });

    test('times a UDP server as well', () async {
      await start(<ProxyNode>[udpNode()]);

      await controller().measureOne(udpNode());

      expect(harness.core.probeCalls, 1);
      expect(container.read(measurementProvider).skipped, 0);
      expect(
        harness.nodeRepository.nodes.single.latency,
        const Duration(milliseconds: 137),
      );
    });

    test('a server that did not answer is recorded as that, not a failure',
        () async {
      final nodes = manyNodes(2);
      await start(nodes);
      for (final node in nodes) {
        harness.core.setLatency('node-${node.id}', null);
      }

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(container.read(measurementProvider).failure, isNull);
      expect(
        harness.nodeRepository.nodes.every(
          (node) => node.latency == null && node.lastCheckedAt != null,
        ),
        isTrue,
      );
    });

    test('measuring one server never touches the tunnel state', () async {
      final nodes = manyNodes(1);
      await start(nodes);

      await controller().measureOne(nodes.single);

      // The regression this pins: a ping used to write its failure into the
      // tunnel controller, which painted the connect button red.
      expect(container.read(tunnelControllerProvider).failure, isNull);
      expect(container.read(tunnelStatusProvider), isA<TunnelIdle>());
    });
  });

  group('TCP', () {
    test('times the handshakes directly and asks no core', () async {
      final nodes = manyNodes(5);
      await start(nodes, method: PingMethod.tcp);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.latencyProbe.asked, hasLength(5));
      expect(harness.core.probeCalls, 0);
      expect(
        harness.nodeRepository.nodes.map((node) => node.latency),
        everyElement(const Duration(milliseconds: 37)),
      );
    });

    test('leaves a UDP server alone and counts it, not marked offline',
        () async {
      final nodes = <ProxyNode>[...manyNodes(2), udpNode()];
      await start(nodes, method: PingMethod.tcp);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.latencyProbe.asked, hasLength(2));
      expect(container.read(measurementProvider).skipped, 1);
      final udp = harness.nodeRepository.nodes.firstWhere(
        (node) => node.id == 'node-udp',
      );
      expect(
        udp.lastCheckedAt,
        isNull,
        reason: 'Nothing listens on TCP there; "offline" would be a lie.',
      );
    });

    test('measuring one UDP server says it was skipped', () async {
      await start(<ProxyNode>[udpNode()], method: PingMethod.tcp);

      await controller().measureOne(udpNode());

      expect(harness.latencyProbe.asked, isEmpty);
      expect(container.read(measurementProvider).skipped, 1);
    });
  });

  test('ICMP sends an echo to every host, UDP servers included', () async {
    final nodes = <ProxyNode>[...manyNodes(2), udpNode()];
    await start(nodes, method: PingMethod.icmp);

    await controller().measureAll(nodes, scopeId: 'sub-1');

    expect(harness.latencyProbe.echoed, hasLength(3));
    expect(harness.latencyProbe.asked, isEmpty);
    expect(harness.core.probeCalls, 0);
    expect(container.read(measurementProvider).skipped, 0);
  });
}
