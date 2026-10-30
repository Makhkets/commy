/// Renders the real screens, puts each in a phone, and writes the pictures
/// the README shows to `docs/screenshots/`.
///
/// Not a test, and deliberately not named `*_test.dart`, so `flutter test`
/// and `melos run test` leave it alone. It exists because the README needs
/// pictures of the application, and a picture of a mock-up is a picture of a
/// plan — this renders the shipping widgets, through the shipping providers,
/// with the real Inter, JetBrains Mono and Lucide faces loaded into the
/// engine, so what ends up in the README is what the code draws.
///
/// Run it from `apps/commy`:
///
/// ```bash
/// flutter test test/screenshots/capture_screenshots.dart
/// ```
///
/// Two passes per picture. The screen is drawn first, at the size and safe
/// areas of a 6.1-inch phone (393 × 852, 59 on top for the status bar and
/// the island, 34 below for the home indicator), three times over. Then that
/// image is laid into a drawn phone — bezel, status bar at 9:41, the island,
/// the home indicator — and photographed again with a transparent ground, so
/// the picture sits on GitHub's light and dark pages alike. The phone is a
/// drawing, not a product shot: no logo, no brand, and the app inside it is
/// the one this repository builds.
///
/// Only the four things that need a device are faked: the tunnel, the
/// repositories, the clipboard and the clock. The data seeded below is
/// obviously synthetic (`example.net`, a zero UUID) — rule R2 applies to
/// screenshots as much as to logs.
///
/// Every capture runs inside [WidgetTester.runAsync]:
/// `RenderRepaintBoundary.toImage` is completed by the engine, and a widget
/// test's fake-async zone never advances real time.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/diagnosis/diagnosis_sheet.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_fonts.dart';
import '../support/commy_test_app.dart';

/// Where the PNGs land, relative to `apps/commy`.
const String _outputDirectory = '../../docs/screenshots';

/// The screen photographed in the first pass.
const ValueKey<String> _appKey = ValueKey<String>('commy-showcase-app');

/// The phone photographed in the second.
const ValueKey<String> _phoneKey = ValueKey<String>('commy-showcase-phone');

/// A 6.1-inch phone, in logical pixels.
const double _screenWidth = 393;
const double _screenHeight = 852;
const Size _screen = Size(_screenWidth, _screenHeight);

/// Its safe areas: the status bar and the island above, the home indicator
/// below.
const double _topInset = 59;
const double _bottomInset = 34;

/// The screen is drawn at this density.
const double _appDensity = 3;

/// The framed picture is written at this one: crisp on a retina display,
/// light enough for a README.
const double _phoneDensity = 2;

/// The phone's body around the screen.
const double _bezel = 13;

/// The thin bright rim on the outside of the body.
const double _rim = 2;

/// The screen's corner, and the body's around it.
const double _screenRadius = 55;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCommyFonts);

  late CommyTestHarness harness;
  tearDown(() => harness.dispose());

  /// One subscription with a quota worth drawing, and its servers.
  List<ProxyNode> nodesOf(String subscriptionId) => <ProxyNode>[
        testNode(id: '$subscriptionId-1', subscriptionId: subscriptionId),
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
        testNode(
          id: '$subscriptionId-4',
          name: 'Helsinki 02',
          countryCode: 'FI',
          subscriptionId: subscriptionId,
          latency: const Duration(milliseconds: 112),
        ),
      ];

  Subscription subscription() => Subscription(
        id: 'sub-1',
        name: 'My panel',
        url: Uri.parse('https://panel.example.net/sub/token'),
        announcement: 'Support: @example',
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

  /// Throughput, pinned: the fake core only produces samples while it runs.
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

  final connected = TunnelStatus.connected(
    since: CommyTestHarness.now.subtract(const Duration(minutes: 42)),
    nodeId: 'sub-1-1',
  );

  Future<void> library() async {
    harness = CommyTestHarness(
      nodes: nodesOf('sub-1'),
      subscriptions: <Subscription>[subscription()],
    );
    await harness.settingsRepository.writeSelectedNodeId('sub-1-1');
  }

  testWidgets('home, connected, light', (tester) async {
    await library();
    await _shoot(
      tester,
      harness,
      'home-connected-light',
      const HomeScreen(),
      dark: false,
      status: connected,
      extra: <Override>[liveTraffic()],
    );
  });

  testWidgets('home, connected, dark', (tester) async {
    await library();
    await _shoot(
      tester,
      harness,
      'home-connected-dark',
      const HomeScreen(),
      dark: true,
      status: connected,
      extra: <Override>[liveTraffic()],
    );
  });

  testWidgets('first run', (tester) async {
    harness = CommyTestHarness();
    await _shoot(
      tester,
      harness,
      'first-run-light',
      const HomeScreen(),
      dark: false,
      status: const TunnelStatus.idle(),
    );
  });

  testWidgets('diagnosis over the main screen', (tester) async {
    await library();
    final node = nodesOf('sub-1').first;
    harness.core.setLatency(SingBoxTags.forNode(node), null);
    final t = Translations();
    await _shoot(
      tester,
      harness,
      'diagnosis-dark',
      Stack(
        children: <Widget>[
          const HomeScreen(),
          // The modal as it stands open: the scrim, and the sheet on it.
          Positioned.fill(
            child: ColoredBox(color: CommyColors.dark.bgScrim),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              type: MaterialType.transparency,
              child: CommySheetSurface(
                title: t.diagnosis.title,
                child: DiagnosisSheet(node: node),
              ),
            ),
          ),
        ],
      ),
      dark: true,
      status: const TunnelStatus.idle(),
    );
  });

  testWidgets('routing', (tester) async {
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
            matcher: 'geosite:category-ads-all',
            action: RuleAction.block,
            sortIndex: 2,
          ),
        ],
      ),
    );
    await _shoot(
      tester,
      harness,
      'routing-light',
      const RoutingScreen(),
      dark: false,
    );
  });

  testWidgets('settings', (tester) async {
    harness = CommyTestHarness();
    await harness.routingRepository.write(
      RoutingPolicy.defaults.copyWith(blockAds: true),
    );
    await _shoot(
      tester,
      harness,
      'settings-dark',
      const SettingsScreen(),
      dark: true,
    );
  });
}

/// Draws [screen] as the app would on a phone, then puts it in one, and
/// writes the result as `<name>.png`.
Future<void> _shoot(
  WidgetTester tester,
  CommyTestHarness harness,
  String name,
  Widget screen, {
  required bool dark,
  TunnelStatus? status,
  List<Override> extra = const <Override>[],
}) async {
  // The first pass: the screen, with its safe areas and nothing moving.
  tester.view
    ..physicalSize = _screen * _appDensity
    ..devicePixelRatio = _appDensity
    ..padding = const FakeViewPadding(
      top: _topInset * _appDensity,
      bottom: _bottomInset * _appDensity,
    )
    ..viewPadding = const FakeViewPadding(
      top: _topInset * _appDensity,
      bottom: _bottomInset * _appDensity,
    );
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _appKey,
      child: harness.wrap(
        screen,
        status: status,
        extra: extra,
        theme: dark ? CommyTheme.dark : CommyTheme.light,
      ),
    ),
  );
  await settle(tester);
  await tester.pump(const Duration(seconds: 1));

  final appBoundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_appKey));
  final shot = await tester.runAsync(
    () => appBoundary.toImage(pixelRatio: _appDensity),
  );
  if (shot == null) {
    fail('$name: the screen produced no image');
  }

  // The second pass: the phone around it.
  const phone = Size(
    _screenWidth + (_bezel + _rim) * 2,
    _screenHeight + (_bezel + _rim) * 2,
  );
  tester.view
    ..physicalSize = phone * _phoneDensity
    ..devicePixelRatio = _phoneDensity
    ..padding = FakeViewPadding.zero
    ..viewPadding = FakeViewPadding.zero;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: _phoneKey,
        child: _Phone(screen: shot, dark: dark),
      ),
    ),
  );
  await tester.pump();

  final phoneBoundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_phoneKey));
  final bytes = await tester.runAsync(() async {
    final image = await phoneBoundary.toImage(pixelRatio: _phoneDensity);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
  shot.dispose();
  if (bytes == null) {
    fail('$name produced no image data');
  }
  final directory = Directory(_outputDirectory);
  if (!directory.existsSync()) {
    directory.createSync(recursive: true);
  }
  File('$_outputDirectory/$name.png').writeAsBytesSync(bytes);
}

/// A drawn phone: a body with a bright rim, the screen in it, and on the
/// screen the status bar, the island and the home indicator.
class _Phone extends StatelessWidget {
  const _Phone({required this.screen, required this.dark});

  final ui.Image screen;
  final bool dark;

  // The body's colours are a drawing's, not the app's: they live here, in
  // the tool that draws the phone, and never in `lib/` (rule R4 is about the
  // product, and this is not part of it).
  static const Color _body = Color(0xFF0B0B0C);
  static const Color _rimColour = Color(0xFF4A4A4F);
  static const Color _island = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    final ink =
        dark ? CommyColors.dark.textPrimary : CommyColors.light.textPrimary;
    const outer = _screenRadius + _bezel + _rim;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _rimColour,
        borderRadius: BorderRadius.circular(outer),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_rim),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _body,
            borderRadius: BorderRadius.circular(outer - _rim),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_bezel),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_screenRadius),
              child: SizedBox.fromSize(
                size: _screen,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: RawImage(
                        image: screen,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: _topInset,
                      child: _StatusBar(ink: ink),
                    ),
                    const Positioned(
                      top: 11,
                      left: (393 - 126) / 2,
                      width: 126,
                      height: 37,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: _island,
                          borderRadius: BorderRadius.all(Radius.circular(19)),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: (_screen.width - 139) / 2,
                      width: 139,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: ink,
                          borderRadius:
                              const BorderRadius.all(Radius.circular(3)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 9:41 on the left of the island; signal, Wi-Fi and a full battery on the
/// right.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.ink});

  final Color ink;

  @override
  Widget build(BuildContext context) {
    // Either side of the island, each centred in its own ear.
    const ear = (393 - 126) / 2;
    return Row(
      children: <Widget>[
        SizedBox(
          width: ear,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 12, top: 3),
              child: Text(
                '9:41',
                style: TextStyle(
                  fontFamily: CommyFonts.ui,
                  package: CommyFonts.package,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  fontVariations: const <ui.FontVariation>[
                    ui.FontVariation('opsz', 17),
                  ],
                  color: ink,
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: ear,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 3),
              child: CustomPaint(
                size: const Size(72, 13),
                painter: _StatusIcons(ink),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The three glyphs of the right ear, drawn rather than taken from a font.
class _StatusIcons extends CustomPainter {
  const _StatusIcons(this.ink);

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = ink;
    final bottom = size.height - 0.5;

    // Signal: four bars, rising.
    const barWidth = 3.0;
    const barGap = 1.7;
    const heights = <double>[4, 6.3, 8.7, 11];
    for (var index = 0; index < heights.length; index++) {
      final left = index * (barWidth + barGap);
      canvas.drawRRect(
        RRect.fromLTRBR(
          left,
          bottom - heights[index],
          left + barWidth,
          bottom,
          const Radius.circular(1),
        ),
        fill,
      );
    }

    // Wi-Fi: three arcs and a dot, a fan opening upwards.
    final wifi = Offset(17 + 6 + 7.7, bottom);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    for (final radius in <double>[3.6, 7.2]) {
      canvas.drawArc(
        Rect.fromCircle(center: wifi, radius: radius),
        -math.pi * 3 / 4,
        math.pi / 2,
        false,
        stroke,
      );
    }
    canvas
      ..drawArc(
        Rect.fromCircle(center: wifi, radius: 10.8),
        -math.pi * 3 / 4,
        math.pi / 2,
        false,
        stroke,
      )
      ..drawCircle(wifi.translate(0, -0.6), 1.3, fill);

    // Battery: an outline, full, and the cap.
    const left = 17 + 6 + 15.4 + 6;
    final body = RRect.fromLTRBR(
      left,
      bottom - 12,
      left + 25,
      bottom,
      const Radius.circular(4),
    );
    canvas
      ..drawRRect(
        body,
        Paint()
          ..color = ink.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      )
      ..drawRRect(body.deflate(2), fill)
      ..drawRRect(
        RRect.fromLTRBR(
          left + 26.2,
          bottom - 8,
          left + 27.6,
          bottom - 4,
          const Radius.circular(0.7),
        ),
        Paint()..color = ink.withValues(alpha: 0.4),
      );
  }

  @override
  bool shouldRepaint(_StatusIcons old) => old.ink != ink;
}
