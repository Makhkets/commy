import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #7: «Замерить все» ran one probe at a time, reported nothing
/// and could not be stopped.
///
/// The batching is not a detail that can be taken on trust — it is the whole
/// point of the change — so the test watches the progress counter and asserts
/// the steps it moves in.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  List<ProxyNode> manyNodes(int count) => <ProxyNode>[
        for (var index = 0; index < count; index++)
          testNode(id: 'node-$index', name: 'Server $index', latency: null),
      ];

  Future<void> start(List<ProxyNode> nodes) async {
    harness = CommyTestHarness(nodes: nodes);
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    // The core only answers a url test while it is running, which is also
    // true of the real one.
    await container.read(tunnelControllerProvider.notifier).connect(
          nodeId: nodes.first.id,
        );
    await harness.core.status
        .firstWhere((status) => status is TunnelConnected)
        .timeout(const Duration(seconds: 5));
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

  test('probes run in batches, not one at a time', () async {
    final nodes = manyNodes(10);
    await start(nodes);
    final steps = watchProgress();

    await controller().measureAll(nodes, scopeId: 'sub-1');

    // 0 when the run is announced, then one step per batch of four, with the
    // last batch short.
    expect(steps, <int>[0, 4, 8, 10]);
    expect(MeasurementController.batchSize, 4);
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

  test('cancelling stops the run and leaves the rest unmeasured', () async {
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
    final measured = harness.nodeRepository.nodes
        .where((node) => node.latency != null)
        .length;
    // The batch that was already in flight is kept — a measurement that came
    // back is still true — but nothing after it was started.
    expect(measured, 4);
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

  /// The header's ping button failed on every press while the tunnel was
  /// down: the only way to measure was to ask a core that was not running.
  /// That is the moment the numbers are wanted — before choosing a server.
  group('with the tunnel down', () {
    Future<void> startIdle(List<ProxyNode> nodes) async {
      harness = CommyTestHarness(nodes: nodes);
      container = ProviderContainer(overrides: harness.overrides());
      addTearDown(() async {
        container.dispose();
        await harness.dispose();
      });
      final handles = <ProviderSubscription<Object?>>[
        container.listen(nodesProvider, (_, __) {}),
        container.listen(coreStatusProvider, (_, __) {}),
      ];
      addTearDown(() {
        for (final handle in handles) {
          handle.close();
        }
      });
      await container.read(nodesProvider.future);
    }

    ProxyNode udpNode() => const ProxyNode(
          id: 'node-udp',
          name: 'Hysteria',
          protocol: Protocol.hysteria2,
          host: 'hy.example.net',
          port: 8443,
        );

    test('a run times the servers directly and asks the core nothing',
        () async {
      final nodes = manyNodes(5);
      await startIdle(nodes);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.latencyProbe.asked, hasLength(5));
      expect(
        harness.nodeRepository.nodes.map((node) => node.latency),
        everyElement(const Duration(milliseconds: 37)),
      );
      final state = container.read(measurementProvider);
      expect(state.isRunning, isFalse);
      expect(state.failure, isNull, reason: 'Not running is not a failure.');
    });

    test('a server that did not answer is recorded as that, not as a failure',
        () async {
      final nodes = manyNodes(2);
      await startIdle(nodes);
      harness.latencyProbe.answer = null;

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(container.read(measurementProvider).failure, isNull);
      expect(
        harness.nodeRepository.nodes.every(
          (node) => node.latency == null && node.lastCheckedAt != null,
        ),
        isTrue,
      );
    });

    test('a UDP server is left alone and counted, not marked offline',
        () async {
      final nodes = <ProxyNode>[...manyNodes(2), udpNode()];
      await startIdle(nodes);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(harness.latencyProbe.asked, hasLength(2));
      expect(container.read(measurementProvider).needTunnel, 1);
      final udp = harness.nodeRepository.nodes.firstWhere(
        (node) => node.id == 'node-udp',
      );
      expect(
        udp.lastCheckedAt,
        isNull,
        reason: 'Nothing listens on TCP there; "offline" would be a lie.',
      );
    });

    test('measuring one UDP server says it needs the tunnel', () async {
      await startIdle(<ProxyNode>[udpNode()]);

      await controller().measureOne(udpNode());

      expect(harness.latencyProbe.asked, isEmpty);
      expect(container.read(measurementProvider).needTunnel, 1);
    });

    test('measuring one server never touches the tunnel state', () async {
      final nodes = manyNodes(1);
      await startIdle(nodes);

      await controller().measureOne(nodes.single);

      // The regression this pins: a ping used to write its failure into the
      // tunnel controller, which painted the connect button red.
      expect(container.read(tunnelControllerProvider).failure, isNull);
      expect(container.read(tunnelStatusProvider), isA<TunnelIdle>());
      expect(
        harness.nodeRepository.nodes.single.latency,
        const Duration(milliseconds: 37),
      );
    });
  });

  test('with the tunnel up the core measures, and the direct probe is unused',
      () async {
    final nodes = manyNodes(3);
    await start(nodes);

    await controller().measureAll(nodes, scopeId: 'sub-1');

    expect(harness.latencyProbe.asked, isEmpty);
  });
}
