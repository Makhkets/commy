/// Renders the real screens and writes them to `docs/screenshots/`.
///
/// Not a test, and deliberately not named `*_test.dart`, so `flutter test`
/// and `melos run test` leave it alone. It exists because the README needs
/// pictures of the application, and a picture of a Figma frame is a picture of
/// a plan — this renders the shipping widgets, through the shipping providers,
/// with the real Inter, JetBrains Mono and Lucide faces loaded into the
/// engine, so what ends up in the README is what the code draws.
///
/// Run it from `apps/commy`:
///
/// ```bash
/// flutter test test/screenshots/capture_screenshots.dart
/// ```
///
/// Only the four things that need a device are faked: the tunnel, the
/// repositories, the clipboard and the clock. The data seeded below is
/// obviously synthetic (`example.net`, a zero UUID) — rule R2 applies to
/// screenshots as much as to logs.
///
/// The whole set runs in one go. It did not use to: a case wrote its PNG and
/// then hung until `flutter test` timed it out, so every screen after the
/// first had to be shot on its own with `--plain-name`. The cause was not the
/// fake core's timer, as the note here used to guess — it was the capture
/// itself. `RenderRepaintBoundary.toImage` is completed by the engine, and a
/// widget test's fake-async zone never advances real time, so the second
/// `await` in [_write] waited on a future nothing in that zone could
/// complete. [WidgetTester.runAsync] steps outside the zone for exactly this,
/// which is also how `matchesGoldenFile` does it.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_fonts.dart';
import '../support/commy_test_app.dart';

/// Where the PNGs land, relative to `apps/commy`.
const String _outputDirectory = '../../docs/screenshots';

/// The frame each screenshot photographs.
const ValueKey<String> _frame = ValueKey<String>('commy-screenshot-frame');

/// A phone, in logical pixels. The design is drawn at this size.
const Size _phone = Size(390, 844);

/// Rendered at 3x, the density the design system assumes for a phone.
const double _density = 3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCommyFonts);

  late CommyTestHarness harness;
  tearDown(() => harness.dispose());

  /// One subscription with a quota worth drawing, and its servers.
  List<ProxyNode> nodesOf(String subscriptionId) => <ProxyNode>[
        testNode(
          id: '$subscriptionId-1',
          subscriptionId: subscriptionId,
        ),
        testNode(
          id: '$subscriptionId-2',
          name: 'Frankfurt 01',
          countryCode: 'DE',
          subscriptionId: subscriptionId,
          latency: const Duration(milliseconds: 62),
        ),
        testNode(
          id: '$subscriptionId-3',
          name: 'Warsaw 10',
          countryCode: 'PL',
          subscriptionId: subscriptionId,
          latency: const Duration(milliseconds: 91),
        ),
      ];

  Subscription subscription() => Subscription(
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

  /// Throughput, pinned: the fake core only produces samples while it runs,
  /// and a hero area of zeroes says nothing about what the screen looks like.
  Override liveTraffic() => trafficProvider.overrideWith(
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

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    TunnelStatus? status,
    List<Override> extra = const <Override>[],
  }) async {
    tester.view
      ..physicalSize = _phone
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _frame,
        child: MediaQuery(
          data: const MediaQueryData(
            size: _phone,
            disableAnimations: true,
          ),
          child: harness.wrap(screen, status: status, extra: extra),
        ),
      ),
    );
    await settle(tester);
    await _write(tester, name);
  }

  testWidgets('01 first run', (tester) async {
    harness = CommyTestHarness();
    await shoot(
      tester,
      '01-first-run',
      const HomeScreen(),
      status: const TunnelStatus.idle(),
    );
  });

  testWidgets('02 home connected', (tester) async {
    harness = CommyTestHarness(
      nodes: nodesOf('sub-1'),
      subscriptions: <Subscription>[subscription()],
    );
    await harness.settingsRepository.writeSelectedNodeId('sub-1-1');
    await shoot(
      tester,
      '02-home-connected',
      const HomeScreen(),
      status: TunnelStatus.connected(
        since: CommyTestHarness.now.subtract(const Duration(minutes: 42)),
        nodeId: 'sub-1-1',
      ),
      extra: <Override>[liveTraffic()],
    );
  });

  testWidgets('03 routing', (tester) async {
    harness = CommyTestHarness();
    await harness.routingRepository.write(
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
            matcher: 'geosite:category-ads',
            action: RuleAction.block,
            sortIndex: 2,
          ),
        ],
      ),
    );
    await shoot(tester, '03-routing', const RoutingScreen());
  });

  testWidgets('04 diagnostics logs', (tester) async {
    harness = CommyTestHarness();
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
    await shoot(tester, '04-diagnostics-logs', const LogsScreen());
  });

  testWidgets('05 settings', (tester) async {
    harness = CommyTestHarness();
    await shoot(tester, '05-settings', const SettingsScreen());
  });
}

/// Photographs the frame and writes it as a PNG.
///
/// Every await here is real I/O, so the whole of it runs outside the test's
/// fake-async zone — see the note at the top of the file.
Future<void> _write(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_frame));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _density);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
  if (bytes == null) {
    fail('$name produced no image data');
  }
  final directory = Directory(_outputDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('$_outputDirectory/$name.png').writeAsBytesSync(bytes);
}
