import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod's default export set; it lives in
// misc.dart. Without this the harness cannot name the type it returns.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_repositories.dart';

/// The harness every widget test in this package pumps through.
///
/// It stands the real provider graph up on fake repositories and a
/// `FakeCoreClient`, so the code under test is the same code that ships —
/// the same controllers, the same use cases, the same `commy_ui` widgets — and
/// only the four things that need a device are swapped.
///
/// Two overrides are about test hygiene rather than isolation. The clock is
/// pinned so a session timer cannot make an assertion flaky, and it also stops
/// `Stream.periodic` from leaving a pending timer that fails the test at
/// teardown.
class CommyTestHarness {
  /// Builds a harness.
  CommyTestHarness({
    List<ProxyNode> nodes = const <ProxyNode>[],
    List<Subscription> subscriptions = const <Subscription>[],
    String? clipboard,
    AppSettings settings = AppSettings.defaults,
    List<ProxyGroup>? coreGroups,
  })  : _coreGroups = coreGroups,
        nodeRepository = FakeNodeRepository(nodes),
        subscriptionRepository = FakeSubscriptionRepository(subscriptions),
        settingsRepository = FakeSettingsRepository(settings: settings),
        routingRepository = FakeRoutingRepository(),
        clipboard = FakeClipboard(clipboard);

  /// A fixed moment, so the session timer never moves under an assertion.
  static final DateTime now = DateTime.utc(2026, 8, 4, 12);

  /// Servers.
  final FakeNodeRepository nodeRepository;

  /// Subscriptions.
  final FakeSubscriptionRepository subscriptionRepository;

  /// Settings, including the selected server.
  final FakeSettingsRepository settingsRepository;

  /// Routing policy and DNS.
  final FakeRoutingRepository routingRepository;

  /// The system clipboard.
  final FakeClipboard clipboard;

  final List<ProxyGroup>? _coreGroups;

  /// The tunnel. Deterministic, seeded, and never touches a device.
  ///
  /// `groups` matters for anything that calls `select`: the fake refuses a tag
  /// that is not in the group, exactly as a real core does, so a switching
  /// test has to declare the outbounds it expects to exist.
  late final FakeCoreClient core = FakeCoreClient(
    startDelay: const Duration(milliseconds: 10),
    checkDelay: const Duration(milliseconds: 10),
    stopDelay: const Duration(milliseconds: 10),
    tick: const Duration(milliseconds: 50),
    groups: _coreGroups,
  );

  /// The log ring the diagnostics screen reads.
  final RingBufferLogRepository logRepository = RingBufferLogRepository();

  /// Releases everything the harness opened.
  Future<void> dispose() async {
    await core.dispose();
    await logRepository.dispose();
    await nodeRepository.dispose();
    await subscriptionRepository.dispose();
    await settingsRepository.dispose();
    await routingRepository.dispose();
  }

  /// The overrides a test scope needs.
  ///
  /// [status] pins what the core reports, for the six-state screen tests.
  /// Leaving it out lets the fake core drive the status itself, which is what
  /// the end-to-end flow test wants.
  List<Override> overrides({TunnelStatus? status}) {
    return <Override>[
      coreClientProvider.overrideWithValue(core),
      clipboardProvider.overrideWithValue(clipboard),
      nodeRepositoryProvider.overrideWithValue(nodeRepository),
      subscriptionRepositoryProvider.overrideWithValue(subscriptionRepository),
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      routingRepositoryProvider.overrideWithValue(routingRepository),
      logRepositoryProvider.overrideWithValue(logRepository),
      clockProvider.overrideWith((ref) => Stream<DateTime>.value(now)),
      if (status != null)
        coreStatusProvider.overrideWith(
          (ref) => Stream<TunnelStatus>.value(status),
        ),
    ];
  }

  /// Wraps [child] in the provider scope, the theme and the translations.
  ///
  /// Not `MaterialApp.router`: a screen test that also stood the router up
  /// would be testing go_router, and a failure in either would look like a
  /// failure in both.
  Widget wrap(Widget child, {TunnelStatus? status}) {
    return ProviderScope(
      overrides: overrides(status: status),
      child: TranslationProvider(
        child: Builder(
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: CommyTheme.dark,
            locale: TranslationProvider.of(context).flutterLocale,
            supportedLocales: AppLocaleUtils.supportedLocales,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: child,
          ),
        ),
      ),
    );
  }
}

/// A server with enough filled in to render a full row.
ProxyNode testNode({
  String id = 'node-1',
  String name = 'Amsterdam 03',
  String countryCode = 'NL',
  String? subscriptionId,
  Duration? latency = const Duration(milliseconds: 48),
}) {
  return ProxyNode(
    id: id,
    name: name,
    protocol: Protocol.vless,
    host: 'nl-03.example.net',
    port: 443,
    countryCode: countryCode,
    subscriptionId: subscriptionId,
    latency: latency,
    params: const <String, Object?>{
      'uuid': '11111111-2222-3333-4444-555555555555',
      'security': 'reality',
      'type': 'tcp',
      'pbk': 'aGVsbG8td29ybGQtcHVibGljLWtleQ',
      'sid': 'ab12cd34',
    },
  );
}

/// Pumps a frame and lets microtasks and the fake core's timers run.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
