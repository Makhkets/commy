import 'dart:io';

import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_fonts.dart';
import '../support/commy_test_app.dart';

/// A photograph of each screen, in both themes.
///
/// The design system has had goldens since it existed; the application had
/// none, and it is the application that assembles those components into
/// something a person looks at. A widget test says the row is there. Only a
/// picture says the row is legible, that light is still a derivation of dark
/// rather than an approximation of it, and that the hero area has not walked
/// off the bottom of a phone.
///
/// The screens are the shipping ones, pumped through the shipping providers on
/// [CommyTestHarness] — the same fakes every other test in this package uses —
/// so a golden moves when the app changes, not when a mock does. Everything
/// they show is pinned: the clock is a constant, the traffic sample is a
/// literal, and no case reads `DateTime.now()`.
///
/// To refresh after a deliberate UI change, on Linux:
///
/// ```bash
/// cd apps/commy && flutter test --update-goldens --tags golden
/// ```
///
/// and look at the diff before committing it. See
/// `.github/workflows/goldens.yml` for the same thing on CI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCommyFonts);

  final nodes = <ProxyNode>[
    testNode(id: 'sub-1-1', subscriptionId: 'sub-1'),
    testNode(
      id: 'sub-1-2',
      name: 'Frankfurt 01',
      countryCode: 'DE',
      subscriptionId: 'sub-1',
      latency: const Duration(milliseconds: 62),
    ),
    testNode(
      id: 'sub-1-3',
      name: 'Warsaw 10',
      countryCode: 'PL',
      subscriptionId: 'sub-1',
      latency: const Duration(milliseconds: 91),
    ),
  ];

  final subscription = Subscription(
    id: 'sub-1',
    name: 'My panel',
    url: Uri.parse('https://panel.example.net/sub/token'),
    announcement: 'id: example · support @example',
    lastUpdatedAt: CommyTestHarness.now.subtract(const Duration(hours: 2)),
    autoUpdate: true,
    updateIntervalHours: 1,
    userInfo: SubscriptionUserInfo(
      upload: 120 * 1024 * 1024 * 1024,
      download: 1000 * 1024 * 1024 * 1024,
      total: 2000 * 1024 * 1024 * 1024,
      expire: CommyTestHarness.now.add(const Duration(days: 18)),
    ),
  );

  // The fake core only produces samples while it runs, and a hero area of
  // zeroes says nothing about what a connected screen looks like.
  final liveTraffic = trafficProvider.overrideWith(
    (ref) => Stream<TrafficSample>.value(
      TrafficSample(
        uplink: 384 * 1024,
        downlink: 3 * 1024 * 1024,
        uplinkTotal: 214 * 1024 * 1024,
        downlinkTotal: 3 * 1024 * 1024 * 1024,
        at: CommyTestHarness.now,
      ),
    ),
  );

  screenGolden(
    'home_first_run',
    screen: const HomeScreen(),
    status: const TunnelStatus.idle(),
  );

  screenGolden(
    'home_connected',
    screen: const HomeScreen(),
    harness: () => CommyTestHarness(
      nodes: nodes,
      subscriptions: <Subscription>[subscription],
    ),
    seed: (harness) =>
        harness.settingsRepository.writeSelectedNodeId('sub-1-1'),
    status: TunnelStatus.connected(
      since: CommyTestHarness.now.subtract(const Duration(minutes: 42)),
      nodeId: 'sub-1-1',
    ),
    extra: <Override>[liveTraffic],
  );

  screenGolden(
    'routing',
    screen: const RoutingScreen(),
    seed: (harness) => harness.routingRepository.write(
      const RoutingPolicy(
        rules: <RoutingRule>[
          RoutingRule(
            id: 'r1',
            matcher: 'geosite:ru',
            action: RuleAction.direct,
          ),
          RoutingRule(
            id: 'r2',
            matcher: 'geoip:private',
            action: RuleAction.direct,
            sortIndex: 1,
          ),
          RoutingRule(
            id: 'r3',
            matcher: 'domain_suffix:ads.example',
            action: RuleAction.block,
            sortIndex: 2,
          ),
        ],
      ),
    ),
  );

  screenGolden(
    'logs',
    screen: const LogsScreen(),
    seed: (harness) async {
      const lines = <(LogLevel, String, String)>[
        (LogLevel.info, 'core', 'sing-box 1.13.16 started'),
        (LogLevel.info, 'tunnel', 'inbound/tun: started at 172.19.0.1/30'),
        (LogLevel.info, 'tunnel', 'reachability confirmed in 48 ms'),
        (LogLevel.warn, 'dns', 'exchange timed out, falling back'),
        (LogLevel.info, 'router', 'match[0] geosite:ru => direct'),
        (LogLevel.error, 'outbound', 'trojan[jp-01]: i/o timeout'),
      ];
      for (var index = 0; index < lines.length; index++) {
        final (level, tag, message) = lines[index];
        await harness.logRepository.append(
          LogLine(
            level: level,
            message: message,
            at: CommyTestHarness.now.add(Duration(seconds: index * 5)),
            tag: tag,
          ),
        );
      }
    },
  );

  // Taller than a phone on purpose: the silence panel is the middle of this
  // screen and the whole point of photographing it. The row that says ad
  // blocking is switched on with no list on disk is in the picture, and so
  // are the three ways of timing a server under "Ping".
  screenGolden(
    'settings',
    size: const Size(390, 2150),
    screen: const SettingsScreen(),
    seed: (harness) => harness.routingRepository.write(
      RoutingPolicy.defaults.copyWith(blockAds: true),
    ),
  );
}

/// A phone, in logical pixels. The design is drawn at this size.
const Size _phone = Size(390, 844);

/// The frame each golden photographs.
const ValueKey<String> _frame = ValueKey<String>('commy-golden-frame');

/// The two themes every golden is taken in.
enum _Theme {
  dark,
  light;

  ThemeData get data =>
      this == _Theme.dark ? CommyTheme.dark : CommyTheme.light;
}

/// Registers one golden per theme for [screen].
void screenGolden(
  String name, {
  required Widget screen,
  Size size = _phone,
  CommyTestHarness Function() harness = CommyTestHarness.new,
  Future<void> Function(CommyTestHarness harness)? seed,
  TunnelStatus? status,
  List<Override> extra = const <Override>[],
}) {
  for (final theme in _Theme.values) {
    testWidgets(
      '$name · ${theme.name}',
      (tester) async {
        final host = harness();
        addTearDown(host.dispose);
        await seed?.call(host);

        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          host.wrap(
            // Inside the app, not around it: `MaterialApp` installs its own
            // `MediaQuery` from the view, so one wrapped outside would be
            // shadowed and the animations it turns off would keep running.
            RepaintBoundary(
              key: _frame,
              child: MediaQuery(
                data: MediaQueryData(size: size, disableAnimations: true),
                child: screen,
              ),
            ),
            status: status,
            extra: extra,
            theme: theme.data,
          ),
        );
        await settle(tester);

        await expectLater(
          find.byKey(_frame),
          matchesGoldenFile('goldens/$name.${theme.name}.png'),
        );
      },
      tags: 'golden',
      // Golden images are Skia output, and Skia rasterises text differently on
      // every platform — the same widget differs by percents between Windows
      // and Linux, which is enough to fail every comparison. Linux owns them,
      // because that is where CI runs; elsewhere the comparison is skipped
      // rather than loosened, since a tolerance wide enough to absorb a font
      // difference also hides the layout regression this is for.
      skip: !Platform.isLinux,
    );
  }
}
