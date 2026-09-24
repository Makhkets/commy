import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/measurement_report.dart';
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
    String probeUrl = AppSettings.defaultLatencyProbeUrl,
  }) async {
    harness = CommyTestHarness(
      nodes: nodes,
      settings: AppSettings(pingMethod: method, latencyProbeUrl: probeUrl),
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

  MeasurementState current() => container.read(measurementProvider);

  /// Every state the run passed through, in order.
  List<MeasurementState> watchStates() {
    final states = <MeasurementState>[];
    final handle = container.listen<MeasurementState>(
      measurementProvider,
      (previous, next) => states.add(next),
    );
    addTearDown(handle.close);
    return states;
  }

  /// What the fake probe core answers for [node].
  void answer(ProxyNode node, int? milliseconds) => harness.core.setLatency(
        'node-${node.id}',
        milliseconds == null ? null : Duration(milliseconds: milliseconds),
      );

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

  /// The owner (2026-09-24): a measurement the user asked for says what it
  /// found. The toast is `NoticeHost`'s; the numbers in it are this
  /// controller's, published once, when the run is over.
  group('the report', () {
    test('counts who answered and names the quickest of them', () async {
      final nodes = manyNodes(4);
      await start(nodes);
      answer(nodes[0], null);
      answer(nodes[1], 90);
      answer(nodes[2], 40);
      answer(nodes[3], null);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      final report = current().report!;
      expect(report.measured, 4);
      expect(report.reachable, 2);
      expect(report.node?.id, 'node-2');
      expect(report.latency, const Duration(milliseconds: 40));
      expect(report.skipped, 0);
      expect(report.isSingle, isFalse);
    });

    test('a tie goes to the server listed first, not the first to return',
        () async {
      final nodes = manyNodes(8);
      await start(nodes);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      // Every server answers in the same 137 ms here, and six of them are
      // in flight at once: whichever came back first is an accident.
      expect(current().report?.node?.id, 'node-0');
    });

    test('a run in which nobody answered names nobody', () async {
      final nodes = manyNodes(3);
      await start(nodes);
      for (final node in nodes) {
        answer(node, null);
      }

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(
        current().report,
        const MeasurementReport(measured: 3, reachable: 0),
      );
    });

    test('the servers the method left alone are in the same report', () async {
      final nodes = <ProxyNode>[...manyNodes(2), udpNode()];
      await start(nodes, method: PingMethod.tcp);

      await controller().measureAll(nodes, scopeId: 'sub-1');

      final report = current().report!;
      expect(report.measured, 2);
      expect(report.reachable, 2);
      expect(report.skipped, 1);
    });

    test('is published once, at the end — the progress carries none', () async {
      final nodes = manyNodes(7);
      await start(nodes);
      final states = watchStates();

      await controller().measureAll(nodes, scopeId: 'sub-1');

      final running = states.where((state) => state.isRunning);
      expect(running, isNotEmpty);
      expect(running.every((state) => state.report == null), isTrue);
      expect(states.where((state) => state.report != null), hasLength(1));
      expect(states.last.report?.measured, 7);
      expect(states.last.isRunning, isFalse);
    });

    test('a cancelled run reports nothing', () async {
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

      expect(current().report, isNull);
      expect(current().failure, isNull);
    });

    test('a failure waits for the end of the run and is said once', () async {
      // No probe page: every GET fails the same way before it starts.
      final nodes = manyNodes(5);
      await start(nodes, probeUrl: '');
      final states = watchStates();

      await controller().measureAll(nodes, scopeId: 'sub-1');

      expect(
        states.where((state) => state.isRunning).map((state) => state.failure),
        everyElement(isNull),
        reason: 'A failure in the progress was announced mid-run, then again.',
      );
      expect(current().failure, isA<ConfigInvalidFailure>());
    });

    test('one server from its menu is named, with its number', () async {
      final nodes = manyNodes(1);
      await start(nodes);
      answer(nodes.single, 90);

      await controller().measureOne(nodes.single);

      final report = current().report!;
      expect(report.isSingle, isTrue);
      expect(report.node?.id, nodes.single.id);
      expect(report.latency, const Duration(milliseconds: 90));
      expect(report.reachable, 1);
    });

    test('one server that did not answer is named too', () async {
      final nodes = manyNodes(1);
      await start(nodes);
      answer(nodes.single, null);

      await controller().measureOne(nodes.single);

      final report = current().report!;
      expect(report.isSingle, isTrue);
      expect(report.node?.id, nodes.single.id);
      expect(report.latency, isNull);
      expect(report.reachable, 0);
    });

    test('one server whose probe failed reports the failure instead', () async {
      final nodes = manyNodes(1);
      await start(nodes, probeUrl: '');

      await controller().measureOne(nodes.single);

      expect(current().failure, isA<ConfigInvalidFailure>());
      expect(current().report, isNull);
    });

    test('once shown, it is cleared with the rest of the outcome', () async {
      final nodes = manyNodes(2);
      await start(nodes, method: PingMethod.tcp);

      await controller().measureAll(nodes, scopeId: 'sub-1');
      controller().clearOutcome();

      expect(current(), MeasurementState.idle);
    });
  });

  group('MeasurementReport.of', () {
    final a = testNode(id: 'a', latency: null);
    final b = testNode(id: 'b', latency: null);

    test('nothing measured is an empty report', () {
      expect(
        MeasurementReport.of(const <(ProxyNode, Duration?)>[], skipped: 3),
        const MeasurementReport(measured: 0, reachable: 0, skipped: 3),
      );
    });

    test('the quickest answer wins', () {
      final report = MeasurementReport.of(<(ProxyNode, Duration?)>[
        (a, const Duration(milliseconds: 90)),
        (b, const Duration(milliseconds: 40)),
      ]);

      expect(report.node, b);
      expect(report.latency, const Duration(milliseconds: 40));
      expect(report.reachable, 2);
    });

    test('a single silent server is still the one named', () {
      final report = MeasurementReport.of(<(ProxyNode, Duration?)>[(a, null)]);

      expect(report.isSingle, isTrue);
      expect(report.node, a);
      expect(report.latency, isNull);
      expect(report.reachable, 0);
    });

    test('several silent servers name none of them', () {
      final report = MeasurementReport.of(<(ProxyNode, Duration?)>[
        (a, null),
        (b, null),
      ]);

      expect(report.node, isNull);
      expect(report.latency, isNull);
    });
  });
}
