/// Each test here pins one promise the app used to make and not keep.
///
/// They are grouped in one file on purpose: the defect they cover is the same
/// defect four times over — a control that writes a value, and no layer that
/// reads it. A regression in any of them looks identical to the user (nothing
/// happens) and identical in CI (everything green), which is exactly why they
/// are worth asserting rather than eyeballing.
library;

import 'dart:async';

import 'package:commy/src/config/selector_config_generator.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` lives in misc.dart, not in the default export set.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

void main() {
  group('hideUnavailable', () {
    final probedAndSilent = testNode(id: 'dead', latency: null)
        .copyWith(lastCheckedAt: DateTime.utc(2026, 8, 4));
    final neverProbed = testNode(id: 'fresh', latency: null);
    final answered = testNode(id: 'alive');

    test('off, every server stays in the list', () {
      const filter = NodeFilter(hideUnavailable: false);

      expect(
        filter.apply(<ProxyNode>[probedAndSilent, neverProbed, answered]),
        hasLength(3),
      );
    });

    test('on, only the server that was asked and stayed silent goes', () {
      const filter = NodeFilter(hideUnavailable: true);

      final visible = filter.apply(
        <ProxyNode>[probedAndSilent, neverProbed, answered],
      );

      expect(visible.map((node) => node.id), <String>['fresh', 'alive']);
    });

    test('a server nobody has measured yet is not "unavailable"', () {
      // docs/05-ux-flows.md: a timeout does not mean the server is gone. A
      // fresh import has measured nothing, and hiding all of it would make a
      // working import look like a broken one.
      const filter = NodeFilter(hideUnavailable: true);

      expect(filter.isVisible(neverProbed), isTrue);
    });
  });

  group('config build warnings', () {
    test('a geosite rule with no rule set on disk is reported, not silent', () {
      final reported = <List<String>>[];
      final node = testNode();
      final generator = SelectorConfigGenerator(
        platform: ConfigPlatform.android,
        knownNodes: () => <ProxyNode>[node],
        onWarnings: reported.add,
      );

      final result = generator.build(
        node: node,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'geosite:ru',
              action: RuleAction.direct,
            ),
          ],
        ),
        dns: DnsSettings.defaults,
        settings: AppSettings.defaults,
        includeClashApi: false,
      );

      expect(result.isOk, isTrue, reason: 'the tunnel must still come up');
      expect(reported, hasLength(1));
      expect(reported.single, isNotEmpty);
      expect(reported.single.join(' '), contains('geosite:ru'));
    });

    test('a clean build reports an empty list, so a stale warning clears', () {
      final reported = <List<String>>[];
      final node = testNode();
      final generator = SelectorConfigGenerator(
        platform: ConfigPlatform.android,
        knownNodes: () => <ProxyNode>[node],
        onWarnings: reported.add,
      );

      final result = generator.build(
        node: node,
        routing: RoutingPolicy.defaults,
        dns: DnsSettings.defaults,
        settings: AppSettings.defaults,
        includeClashApi: false,
      );

      expect(result.isOk, isTrue);
      expect(reported.single, isEmpty);
    });
  });

  group('the checking state', () {
    late CommyTestHarness harness;

    setUp(() => harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]));
    tearDown(() => harness.dispose());

    test('a tunnel that comes up is probed, and says so while it probes',
        () async {
      final core = _GatedProbeCore();
      addTearDown(core.dispose);
      await harness.settingsRepository.writeSelectedNodeId('node-1');

      // Built by hand rather than from `harness.overrides()`: that list
      // already pins the core, and Riverpod refuses the same provider twice.
      final container = ProviderContainer(
        overrides: <Override>[
          coreClientProvider.overrideWithValue(core),
          nodeRepositoryProvider.overrideWithValue(harness.nodeRepository),
          settingsRepositoryProvider
              .overrideWithValue(harness.settingsRepository),
          routingRepositoryProvider
              .overrideWithValue(harness.routingRepository),
          logRepositoryProvider.overrideWithValue(harness.logRepository),
          clipboardProvider.overrideWithValue(harness.clipboard),
          // The status is pinned so the fake's own transitions cannot stand in
          // for the derivation under test.
          coreStatusProvider.overrideWith(
            (ref) => Stream<TunnelStatus>.value(
              TunnelStatus.connected(
                since: CommyTestHarness.now,
                nodeId: 'node-1',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Both have to have landed before the probe runs: `check()` resolves the
      // selected node against the stored list and gives up quietly if either
      // is still in flight.
      await container.read(selectedNodeIdProvider.future);
      container
        ..listen(nodesProvider, (_, __) {})
        ..listen(autoCheckProvider, (_, __) {});
      await pumpEventQueue();

      expect(
        container.read(tunnelStatusProvider),
        isA<TunnelChecking>(),
        reason: 'the core never reports this state; the app derives it',
      );

      core.answer(const Duration(milliseconds: 42));
      await pumpEventQueue();

      expect(container.read(tunnelStatusProvider), isA<TunnelConnected>());
      expect(
        container.read(tunnelControllerProvider).notice,
        const TunnelNotice(TunnelNoticeKind.checkPassed, milliseconds: 42),
      );
    });
  });

  group('autoConnect', () {
    test('on, the tunnel comes up with nobody touching the button', () async {
      final harness = CommyTestHarness(
        nodes: <ProxyNode>[testNode()],
        settings: const AppSettings(autoConnect: true),
      );
      addTearDown(harness.dispose);
      await harness.settingsRepository.writeSelectedNodeId('node-1');

      final container = ProviderContainer(overrides: harness.overrides());
      addTearDown(container.dispose);

      await container.read(selectedNodeIdProvider.future);
      container.listen(autoConnectProvider, (_, __) {});
      await pumpEventQueue();

      expect(harness.core.isRunning, isTrue);
    });

    test('off, nothing starts on its own', () async {
      final harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
      addTearDown(harness.dispose);
      await harness.settingsRepository.writeSelectedNodeId('node-1');

      final container = ProviderContainer(overrides: harness.overrides());
      addTearDown(container.dispose);

      await container.read(selectedNodeIdProvider.future);
      container.listen(autoConnectProvider, (_, __) {});
      await pumpEventQueue();

      expect(harness.core.isRunning, isFalse);
    });

    test('enabling it later does not connect mid-session', () async {
      // "Автоподключение при запуске" is what the row says. Reacting to the
      // switch itself would make it mean something else.
      final harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
      addTearDown(harness.dispose);
      await harness.settingsRepository.writeSelectedNodeId('node-1');

      final container = ProviderContainer(overrides: harness.overrides());
      addTearDown(container.dispose);

      await container.read(selectedNodeIdProvider.future);
      container.listen(autoConnectProvider, (_, __) {});
      await pumpEventQueue();

      await harness.settingsRepository.write(
        const AppSettings(autoConnect: true),
      );
      await pumpEventQueue();

      expect(harness.core.isRunning, isFalse);
    });
  });
}

/// A core whose reachability probe answers only when the test says so.
///
/// `FakeCoreClient.urlTest` returns immediately, which makes the transient
/// `checking` state impossible to observe without a race.
class _GatedProbeCore extends FakeCoreClient {
  _GatedProbeCore()
      : super(
          startDelay: const Duration(milliseconds: 10),
          stopDelay: const Duration(milliseconds: 10),
        );

  final Completer<Duration?> _gate = Completer<Duration?>();

  /// Lets the pending probe finish with [value].
  void answer(Duration? value) => _gate.complete(value);

  @override
  Future<Duration?> urlTest(String tag, Uri probe) => _gate.future;
}
