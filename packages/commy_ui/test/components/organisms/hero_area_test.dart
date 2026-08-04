import 'dart:typed_data';

import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/components/organisms/check_button.dart';
import 'package:commy_ui/src/components/organisms/connect_button.dart';
import 'package:commy_ui/src/components/organisms/connect_state.dart';
import 'package:commy_ui/src/components/organisms/metrics_strip.dart';
import 'package:commy_ui/src/components/organisms/selected_node.dart';
import 'package:commy_ui/src/theme/theme.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/connect_tokens.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in the real theme, with the accessibility knobs exposed.
Widget _host({
  required Widget child,
  bool dark = true,
  double textScale = 1,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    theme: dark ? CommyTheme.dark : CommyTheme.light,
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Renders one state of the button on the canvas colour and reads the pixels
/// back, so that geometry can be asserted rather than eyeballed.
Future<_Pixels> _paint(
  WidgetTester tester,
  ConnectState state, {
  bool reduceMotion = true,
}) async {
  const key = ValueKey<String>('connect-capture');
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      reduceMotion: reduceMotion,
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: CommyColors.dark.bgCanvas,
          child: SizedBox.square(
            dimension: CommyConnectTokens.containerSize,
            child: ConnectButton(
              state: state,
              onPressed: null,
              semanticLabel: 'connect',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));

  late ByteData data;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage();
    data = (await image.toByteData())!;
  });
  return _Pixels(data, CommyConnectTokens.containerSize.toInt());
}

class _Pixels {
  _Pixels(this.data, this.side);

  final ByteData data;
  final int side;

  /// Reads the pixel [dx] right of and [dy] below the centre of the disc.
  Color at(int dx, int dy) {
    final index = ((side ~/ 2 + dy) * side + side ~/ 2 + dx) * 4;
    return Color.fromARGB(
      data.getUint8(index + 3),
      data.getUint8(index),
      data.getUint8(index + 1),
      data.getUint8(index + 2),
    );
  }
}

/// Channel-wise comparison with room for one pixel of antialiasing.
Matcher _closeToColor(Color expected, {int tolerance = 16}) => predicate<Color>(
      (actual) =>
          (actual.r - expected.r).abs() * 255 <= tolerance &&
          (actual.g - expected.g).abs() * 255 <= tolerance &&
          (actual.b - expected.b).abs() * 255 <= tolerance,
      'within $tolerance of $expected',
    );

void main() {
  group('ConnectButton', () {
    testWidgets('renders every state in both themes', (tester) async {
      for (final dark in <bool>[true, false]) {
        for (final state in ConnectState.values) {
          await tester.pumpWidget(
            _host(
              dark: dark,
              child: ConnectButton(
                state: state,
                onPressed: () {},
                semanticLabel: 'connect',
                semanticValue: state.name,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: '$state dark=$dark');
        }
      }
    });

    testWidgets('measures 240 dp and takes taps across the disc', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          child: ConnectButton(
            state: ConnectState.idle,
            onPressed: () => taps++,
            semanticLabel: 'connect',
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ConnectButton)),
        const Size.square(CommyConnectTokens.containerSize),
      );

      final center = tester.getCenter(find.byType(ConnectButton));
      await tester.tapAt(center + const Offset(80, 0));
      await tester.pump();
      expect(taps, 1, reason: 'the whole disc is the tap target');

      await tester.tapAt(center + const Offset(115, 0));
      await tester.pump();
      expect(taps, 1, reason: 'the halo is not part of the tap target');
    });

    testWidgets('stops animating under reduced motion', (tester) async {
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: ConnectButton(
            state: ConnectState.starting,
            onPressed: () {},
            semanticLabel: 'connect',
          ),
        ),
      );
      // Would time out if the arc kept turning or the glow kept breathing.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('settles after a state change', (tester) async {
      await tester.pumpWidget(
        _host(
          child: ConnectButton(
            state: ConnectState.starting,
            onPressed: () {},
            semanticLabel: 'connect',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(
        _host(
          child: ConnectButton(
            state: ConnectState.error,
            onPressed: () {},
            semanticLabel: 'connect',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('carries its state to assistive technology', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          child: ConnectButton(
            state: ConnectState.connected,
            onPressed: () {},
            semanticLabel: 'Отключиться',
            semanticValue: 'Подключено',
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Отключиться'),
        findsOneWidget,
        reason: 'colour must not be the only carrier of state',
      );
      handle.dispose();
    });

    testWidgets('paints halo, disc and ring where the spec puts them', (
      tester,
    ) async {
      const colors = CommyColors.dark;
      final idle = await _paint(tester, ConnectState.idle);

      expect(idle.at(0, 60), _closeToColor(colors.bgRaised));
      expect(idle.at(95, 0), _closeToColor(colors.bgSurface));
      expect(idle.at(85, 0), _closeToColor(colors.borderDefault));
      expect(
        idle.at(110, 0),
        _closeToColor(colors.bgCanvas, tolerance: 1),
        reason: 'idle does not glow',
      );
    });

    testWidgets('glows on a ring, never through the disc', (tester) async {
      const colors = CommyColors.dark;
      final connected = await _paint(tester, ConnectState.connected);

      expect(connected.at(85, 0), _closeToColor(colors.statusConnected));
      // The glow reaches past the ring outwards...
      expect(connected.at(95, 0).g, greaterThan(connected.at(105, 0).g));
      // ...but the middle of the disc stays the flat wash it started as.
      final middle = connected.at(30, 30);
      expect(middle.r * 255, lessThan(24), reason: 'no light in the middle');
      expect(middle.g * 255, lessThan(64), reason: 'no light in the middle');
    });

    testWidgets('draws the starting arc 270° clockwise from the top', (
      tester,
    ) async {
      const colors = CommyColors.dark;
      final starting = await _paint(tester, ConnectState.starting);

      // A 1.5 dp stroke never fills a pixel, so the arc is asserted by its
      // hue against the gap rather than by an exact colour.
      for (final on in <Color>[starting.at(61, -61), starting.at(-61, 61)]) {
        expect(on.r, greaterThan(on.g), reason: 'amber, not grey');
        expect(on.r * 255, greaterThan(150));
      }
      expect(
        starting.at(-61, -61),
        _closeToColor(colors.borderSubtle, tolerance: 4),
        reason: 'the 90° gap sits in the upper-left quadrant',
      );
    });
  });

  group('MetricsStrip', () {
    testWidgets('shows zeros while nothing is connected', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const MetricsStrip(
            uplink: 25600,
            downlink: 37888,
            session: Duration(minutes: 12, seconds: 47),
          ),
        ),
      );
      expect(find.text('00:00:00'), findsOneWidget);
      expect(find.text('0 B/s'), findsNWidgets(2));
    });

    testWidgets('shows live figures once the tunnel is up', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const MetricsStrip(
            uplink: 25600,
            downlink: 37888,
            session: Duration(minutes: 12, seconds: 47),
            isActive: true,
          ),
        ),
      );
      expect(find.text('00:12:47'), findsOneWidget);
      expect(find.text('25 KB/s'), findsOneWidget);
      expect(find.text('37 KB/s'), findsOneWidget);
    });
  });

  group('SelectedNode', () {
    testWidgets('opens the list and keeps a 48 dp target', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          child: SelectedNode(
            name: 'Amsterdam 03',
            onTap: () => opened++,
            flag: const SizedBox(
              width: CommySizes.flagWidth,
              height: CommySizes.flagHeight,
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(SelectedNode)).height,
        greaterThanOrEqualTo(CommySizes.minTapTarget),
      );
      await tester.tap(find.text('Amsterdam 03'));
      await tester.pump();
      expect(opened, 1);
    });

    testWidgets('drops the chevron when there is nothing to open', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(child: const SelectedNode(name: 'Amsterdam 03', onTap: null)),
      );
      expect(find.byType(Icon), findsNothing);
    });
  });

  group('CheckButton', () {
    testWidgets('sits at the leading edge and keeps a 48 dp target', (
      tester,
    ) async {
      var checks = 0;
      await tester.pumpWidget(
        _host(
          child: SizedBox(
            width: 320,
            child: CheckButton(
              label: 'Проверить',
              onPressed: () => checks++,
            ),
          ),
        ),
      );
      final box = tester.getRect(find.byType(InkWell));
      expect(box.height, greaterThanOrEqualTo(CommySizes.minTapTarget));
      expect(
        box.left,
        tester.getRect(find.byType(CheckButton)).left,
        reason: 'never centred under the connect button',
      );
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(checks, 1);
    });

    testWidgets('ignores taps while a probe is running', (tester) async {
      var checks = 0;
      await tester.pumpWidget(
        _host(
          child: CheckButton(
            label: 'Проверить',
            onPressed: () => checks++,
            isChecking: true,
          ),
        ),
      );
      await tester.tap(find.text('Проверить'));
      await tester.pump();
      expect(checks, 0);
    });
  });

  group('the hero area as a whole', () {
    testWidgets('does not overflow at 200% text on a 320 dp screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          textScale: 2,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                const MetricsStrip(
                  uplink: 25600,
                  downlink: 37888,
                  session: Duration(minutes: 12, seconds: 47),
                  isActive: true,
                  uplinkLabel: 'Отдача',
                  sessionLabel: 'Сессия',
                  downlinkLabel: 'Загрузка',
                ),
                ConnectButton(
                  state: ConnectState.connected,
                  onPressed: () {},
                  semanticLabel: 'Отключиться',
                ),
                SelectedNode(
                  name: 'Amsterdam 03 — очень длинное имя узла',
                  onTap: () {},
                  flag: const SizedBox(
                    width: CommySizes.flagWidth,
                    height: CommySizes.flagHeight,
                  ),
                ),
                CheckButton(label: 'Проверить', onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('ConnectState', () {
    test('projects every tunnel status', () {
      final now = DateTime.utc(2026);
      expect(ConnectState.of(const TunnelStatus.idle()), ConnectState.idle);
      expect(
        ConnectState.of(const TunnelStatus.starting()),
        ConnectState.starting,
      );
      expect(
        ConnectState.of(TunnelStatus.checking(since: now)),
        ConnectState.checking,
      );
      expect(
        ConnectState.of(TunnelStatus.connected(since: now)),
        ConnectState.connected,
      );
      expect(
        ConnectState.of(const TunnelStatus.stopping()),
        ConnectState.stopping,
      );
      expect(
        ConnectState.of(
          const TunnelStatus.error(CommyFailure.permissionDenied()),
        ),
        ConnectState.error,
      );
    });

    test('answers what the screen may show', () {
      expect(ConnectState.connected.showsCheckButton, isTrue);
      expect(ConnectState.checking.showsCheckButton, isTrue);
      expect(ConnectState.idle.showsCheckButton, isFalse);
      expect(ConnectState.starting.showsCheckButton, isFalse);
      expect(ConnectState.connected.pulses, isTrue);
      expect(ConnectState.error.glows, isTrue);
      expect(ConnectState.error.pulses, isFalse);
      expect(ConnectState.starting.showsArc, isTrue);
      expect(ConnectState.stopping.isTransitional, isTrue);
    });
  });
}
