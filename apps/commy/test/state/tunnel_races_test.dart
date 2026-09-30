import 'dart:async';

import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The tunnel controller where two things happen at once.
///
/// `FakeCoreClient` answers `start` and `reload` the moment they are called,
/// so every other test sees a controller that is never busy for long. The
/// device is not like that: a start waits for the service for up to half a
/// minute, and a reload closes one box and builds the next. These cases hold
/// the core's answer open and act in the gap.
void main() {
  late _HeldHarness harness;
  late ProviderContainer container;

  /// Past the live-reload settle window, with room for the core to restart.
  const settled = Duration(milliseconds: 600);

  Future<void> start({
    List<ProxyNode>? nodes,
    List<Subscription> subscriptions = const <Subscription>[],
    String? selected = 'node-1',
    Duration startDelay = const Duration(milliseconds: 10),
  }) async {
    harness = _HeldHarness(
      nodes: nodes ?? <ProxyNode>[testNode()],
      subscriptions: subscriptions,
      startDelay: startDelay,
    );
    if (selected != null) {
      await harness.settingsRepository.writeSelectedNodeId(selected);
    }
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    // What the app keeps listened to from its root and its home screen.
    final handles = <ProviderSubscription<Object?>>[
      container.listen(liveReloadProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(tunnelControllerProvider, (_, __) {}),
      container.listen(nodesProvider, (_, __) {}),
      container.listen(selectedNodeIdProvider, (_, __) {}),
      container.listen(routingPolicyProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    await container.read(nodesProvider.future);
    await container.read(routingPolicyProvider.future);
    await container.read(settingsProvider.future);
    await pumpEventQueue();
  }

  TunnelController tunnel() =>
      container.read(tunnelControllerProvider.notifier);

  Future<void> waitFor(bool Function() done) async {
    for (var tries = 0; tries < 200 && !done(); tries++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'timed out');
  }

  Future<void> connected() async {
    expect(await tunnel().connect(), isTrue);
    await waitFor(
      () => container.read(coreStatusProvider).value is TunnelConnected,
    );
  }

  group('an edit that lands while a reload is running', () {
    test('is applied by one more reload once that one is done', () async {
      await start();
      await connected();
      harness.core.holdReloads();

      await harness.routingRepository.write(
        RoutingPolicy.defaults.copyWith(blockAds: true),
      );
      await waitFor(() => harness.core.reloadCalls == 1);
      // The first reload read the stores before this one.
      await harness.routingRepository.write(
        RoutingPolicy.defaults.copyWith(blockAds: true, bypassLan: false),
      );
      await Future<void>.delayed(settled);
      expect(harness.core.reloadCalls, 1, reason: 'still waiting its turn');

      harness.core.releaseReloads();
      await waitFor(() => harness.core.reloadCalls == 2);
      await waitFor(() => !container.read(tunnelControllerProvider).isBusy);

      // Without bypassLan the private-address rule is gone from the document.
      expect(
        harness.core.lastConfig!.encode(),
        isNot(contains('ip_is_private')),
      );
    });
  });

  group('the spinning button', () {
    // A core that stays on "starting" until it is told otherwise.
    const slowStart = Duration(hours: 1);

    test('calls off a connect the core has not answered yet', () async {
      await start(startDelay: slowStart);
      harness.core.holdStarts();

      final connecting = tunnel().connect();
      await waitFor(() => harness.core.startCalls == 1);
      expect(container.read(tunnelControllerProvider).isBusy, isTrue);
      expect(container.read(coreStatusProvider).value, isA<TunnelStarting>());

      // What the button does on a tap while it spins.
      await tunnel().toggle();
      harness.core.releaseStarts();
      await connecting;
      await waitFor(
        () => container.read(coreStatusProvider).value is TunnelIdle,
      );

      expect(harness.core.stopCalls, greaterThanOrEqualTo(1));
      expect(harness.core.isRunning, isFalse);
      final state = container.read(tunnelControllerProvider);
      expect(state.isBusy, isFalse);
      expect(state.failure, isNull);
    });

    test('a start that came up after the cancel is taken down again', () async {
      // A stop sent before the service existed could not reach the start,
      // which then went ahead: the connect sees it was called off.
      await start(startDelay: slowStart);
      harness.core
        ..holdStarts()
        ..ignoreStops = true;

      final connecting = tunnel().connect();
      await waitFor(() => harness.core.startCalls == 1);
      final stopping = tunnel().disconnect();
      await stopping;
      harness.core
        ..ignoreStops = false
        ..releaseStarts();
      await connecting;
      await waitFor(() => !harness.core.isRunning);

      expect(harness.core.stopCalls, 2);
      expect(container.read(tunnelControllerProvider).isBusy, isFalse);
    });
  });

  group('a check that outlives its tunnel', () {
    test('says nothing once the tunnel is gone', () async {
      await start();
      await connected();
      await waitFor(
        () => !container.read(tunnelControllerProvider).isChecking,
      );
      harness.core.holdProbes();

      final checking = tunnel().check();
      await waitFor(() => container.read(tunnelControllerProvider).isChecking);
      await tunnel().disconnect();
      harness.core.releaseProbes(null);
      await checking;

      final state = container.read(tunnelControllerProvider);
      expect(state.notice, isNull);
      expect(state.failure, isNull);
      expect(state.isChecking, isFalse);
    });
  });

  group('a selection that is no longer a server', () {
    test('the button connects to the first server there is', () async {
      await start(selected: 'gone');

      expect(await tunnel().connect(), isTrue);

      expect(container.read(tunnelControllerProvider).failure, isNull);
      expect(harness.settingsRepository.selectedNodeId, 'node-1');
    });

    test("deleting the running server's subscription stops the tunnel",
        () async {
      final subscription = testSubscription();
      await start(
        nodes: <ProxyNode>[
          testNode(subscriptionId: subscription.id),
          testNode(id: 'node-2', name: 'Manual'),
        ],
        subscriptions: <Subscription>[subscription],
      );
      await connected();

      await container
          .read(subscriptionControllerProvider.notifier)
          .delete(subscription.id);
      await waitFor(
        () => container.read(coreStatusProvider).value is TunnelIdle,
      );

      expect(harness.core.isRunning, isFalse);
      expect(harness.settingsRepository.selectedNodeId, isNull);
      expect(harness.subscriptionRepository.items, isEmpty);
    });
  });

  group('a rule set that arrives while the tunnel is up', () {
    test('reaches the running core without a reconnect', () async {
      await start();
      await harness.routingRepository.write(
        RoutingPolicy.defaults.copyWith(
          mode: RoutingMode.rules,
          rules: const <RoutingRule>[
            RoutingRule(
              id: 'ru',
              matcher: 'geosite:ru',
              action: RuleAction.direct,
            ),
          ],
        ),
      );
      await Future<void>.delayed(settled);
      await connected();
      expect(harness.core.lastConfig!.encode(), isNot(contains('geosite-ru')));

      await harness.ruleSetRepository.download(
        tag: 'geosite-ru',
        from: Uri.parse('https://mirror.example/geosite-ru.srs'),
      );
      await Future<void>.delayed(settled);
      await waitFor(
        () => harness.core.lastConfig!.encode().contains('geosite-ru'),
      );

      expect(harness.core.startCalls, 1, reason: 'reload, not restart');
    });
  });
}

/// The harness, over a core whose answers the test can hold open.
class _HeldHarness extends CommyTestHarness {
  _HeldHarness({
    required this.startDelay,
    super.nodes,
    super.subscriptions,
  });

  /// How long the core stays on "starting" once it has been started.
  final Duration startDelay;

  @override
  // The harness's core is a field, and this is the one test that needs a
  // different one behind every override the harness hands out.
  // ignore: overridden_fields
  late final _HeldCore core = _HeldCore(startDelay: startDelay);
}

/// A fake core that answers `start`, `reload` and `urlTest` when told to.
class _HeldCore extends FakeCoreClient {
  _HeldCore({required super.startDelay})
      : super(
          checkDelay: const Duration(milliseconds: 10),
          stopDelay: const Duration(milliseconds: 10),
          tick: const Duration(milliseconds: 50),
        );

  Completer<void>? _starts;
  Completer<void>? _reloads;
  Completer<Duration?>? _probes;

  /// Stops that are counted and do nothing, like one sent before the
  /// service that would carry it out exists.
  bool ignoreStops = false;

  void holdStarts() => _starts = Completer<void>();
  void releaseStarts() => _starts?.complete();
  void holdReloads() => _reloads = Completer<void>();
  void releaseReloads() => _reloads?.complete();
  void holdProbes() => _probes = Completer<Duration?>();
  void releaseProbes(Duration? value) => _probes?.complete(value);

  /// Reports "starting" straight away, as the service does, and answers
  /// only when the test releases it.
  @override
  Future<void> start(CoreConfig config) async {
    await super.start(config);
    final gate = _starts;
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<void> stop() async {
    if (ignoreStops) {
      stopCalls++;
      return;
    }
    await super.stop();
  }

  @override
  Future<void> reload(CoreConfig config) async {
    final gate = _reloads;
    await super.reload(config);
    if (gate != null) {
      await gate.future;
    }
  }

  @override
  Future<Duration?> urlTest(String tag, Uri probe) {
    final gate = _probes;
    return gate == null ? super.urlTest(tag, probe) : gate.future;
  }
}
