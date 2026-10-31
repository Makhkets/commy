import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/molecules/node_tag_line.dart';
import 'package:commy_ui/src/components/organisms/connect_state.dart';
import 'package:commy_ui/src/components/organisms/connection_route.dart';
import 'package:commy_ui/src/components/organisms/metrics_strip.dart';
import 'package:commy_ui/src/theme/theme.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';
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
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    ),
  );
}

ConnectionRoute _route({
  ConnectState state = ConnectState.idle,
  String serverName = 'Amsterdam 03',
  VoidCallback? onServerTap,
  VoidCallback? onCheck,
  bool isChecking = false,
  RouteBreak? breakAt,
  String? internetStatus,
}) {
  return ConnectionRoute(
    state: state,
    deviceLabel: 'Это устройство',
    serverName: serverName,
    internetLabel: 'Интернет',
    tags: const <NodeTag>[NodeTag('VLESS'), NodeTag('TCP')],
    latency: const Duration(milliseconds: 48),
    onServerTap: onServerTap,
    serverSemanticLabel: 'Выбрать сервер',
    checkLabel: 'Проверить доступ',
    onCheck: onCheck,
    isChecking: isChecking,
    breakAt: breakAt,
    internetStatus: internetStatus,
  );
}

void main() {
  group('ConnectionRoute', () {
    testWidgets('draws the three stops and names the server', (tester) async {
      await tester.pumpWidget(_host(child: _route(), reduceMotion: true));
      expect(find.text('Это устройство'), findsOneWidget);
      expect(find.text('Amsterdam 03'), findsOneWidget);
      expect(find.text('Интернет'), findsOneWidget);
      expect(find.text('48 ms'), findsOneWidget);
    });

    testWidgets('the server stop opens the picker, at least 48 dp tall', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(onServerTap: () => opened++),
        ),
      );
      expect(find.byIcon(CommyIcons.chevronDown), findsOneWidget);
      await tester.tap(find.text('Amsterdam 03'));
      expect(opened, 1);
      final row = find.ancestor(
        of: find.text('Amsterdam 03'),
        matching: find.byType(InkWell),
      );
      expect(
        tester.getSize(row.first).height,
        greaterThanOrEqualTo(CommySizes.minTapTarget),
      );
    });

    testWidgets('draws no chevron when there is nothing to pick', (
      tester,
    ) async {
      await tester.pumpWidget(_host(reduceMotion: true, child: _route()));
      expect(find.byIcon(CommyIcons.chevronDown), findsNothing);
    });

    testWidgets('the check sits on the internet stop and waits while busy', (
      tester,
    ) async {
      var checks = 0;
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(
            state: ConnectState.connected,
            onCheck: () => checks++,
          ),
        ),
      );
      await tester.tap(find.text('Проверить доступ'));
      expect(checks, 1);
      // On one line with the word it belongs to, not hanging below it.
      expect(
        tester.getCenter(find.text('Проверить доступ')).dy,
        moreOrLessEquals(
          tester.getCenter(find.text('Интернет')).dy,
          epsilon: 1,
        ),
      );

      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(
            state: ConnectState.connected,
            onCheck: () => checks++,
            isChecking: true,
          ),
        ),
      );
      await tester.tap(find.text('Проверить доступ'));
      expect(checks, 1);
    });

    testWidgets(
        'a leg being built travels, and keeps still when motion is '
        'reduced', (tester) async {
      await tester.pumpWidget(
        _host(child: _route(state: ConnectState.starting)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(state: ConnectState.starting),
        ),
      );
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('settles once the route is drawn', (tester) async {
      await tester.pumpWidget(_host(child: _route()));
      await tester.pumpWidget(
        _host(child: _route(state: ConnectState.connected)),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('marks the stop where the route broke with a cross', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(
            state: ConnectState.error,
            breakAt: RouteBreak.server,
          ),
        ),
      );
      expect(find.byIcon(CommyIcons.close), findsOneWidget);

      await tester.pumpWidget(
        _host(reduceMotion: true, child: _route(state: ConnectState.error)),
      );
      expect(find.byIcon(CommyIcons.close), findsNothing);
    });

    testWidgets('says what the access check found under the internet stop', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: _route(
            state: ConnectState.connected,
            internetStatus: 'Доступ есть, 52 мс',
          ),
        ),
      );
      expect(find.text('Доступ есть, 52 мс'), findsOneWidget);
    });

    testWidgets('does not overflow at 200% text on a 320 dp screen', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          textScale: 2,
          reduceMotion: true,
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
                _route(
                  state: ConnectState.connected,
                  serverName: 'Amsterdam 03 — очень длинное имя узла',
                  onServerTap: () {},
                  onCheck: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });
  });

  group('RouteSteps', () {
    testWidgets(
        'a cross on the layer that broke, and the details beside '
        'each', (tester) async {
      await tester.pumpWidget(
        _host(
          reduceMotion: true,
          child: const RouteSteps(
            steps: <RouteStep>[
              RouteStep(
                label: 'Имя сервера',
                state: RouteStepState.passed,
                detail: '198.51.100.7',
              ),
              RouteStep(
                label: 'Порт открыт',
                state: RouteStepState.passed,
                detail: '37 мс',
              ),
              RouteStep(
                label: 'Запрос через сервер',
                state: RouteStepState.failed,
              ),
            ],
          ),
        ),
      );
      expect(find.text('198.51.100.7'), findsOneWidget);
      expect(find.text('37 мс'), findsOneWidget);
      expect(find.byIcon(CommyIcons.close), findsOneWidget);
    });

    testWidgets('the layer being checked travels', (tester) async {
      await tester.pumpWidget(
        _host(
          child: const RouteSteps(
            steps: <RouteStep>[
              RouteStep(label: 'Имя сервера', state: RouteStepState.passed),
              RouteStep(label: 'Порт открыт', state: RouteStepState.running),
              RouteStep(label: 'TLS', state: RouteStepState.pending),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.hasRunningAnimations, isTrue);
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

    testWidgets('centres the clock between download and upload',
        (tester) async {
      await tester.pumpWidget(
        _host(
          child: const MetricsStrip(
            uplink: 5,
            downlink: 37888,
            session: Duration(minutes: 12, seconds: 47),
            isActive: true,
          ),
        ),
      );
      expect(find.text('00:12:47'), findsOneWidget);
      expect(find.text('5 B/s'), findsOneWidget);
      expect(find.text('37 KB/s'), findsOneWidget);
      final clock = tester.getCenter(find.text('00:12:47'));
      final strip = tester.getRect(find.byType(MetricsStrip));
      expect(clock.dx, closeTo(strip.center.dx, 0.01));
      expect(
        tester.getCenter(find.text('37 KB/s')).dx,
        lessThan(clock.dx),
      );
      expect(tester.getCenter(find.text('5 B/s')).dx, greaterThan(clock.dx));
    });

    testWidgets('keeps session totals under their respective rates', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          child: MetricsStrip(
            uplink: 25600,
            downlink: 37888,
            session: const Duration(minutes: 12, seconds: 47),
            isActive: true,
            uplinkLabel: 'Upload',
            sessionLabel: 'Time',
            downlinkLabel: 'Download',
            uplinkTotal: 214 * 1024 * 1024,
            downlinkTotal: 3 * 1024 * 1024 * 1024,
            totalLabel: (value) => '$value total',
          ),
        ),
      );
      final down = tester.getCenter(find.text('37 KB/s'));
      final up = tester.getCenter(find.text('25 KB/s'));
      final downTotal = tester.getCenter(find.text('3.0 GB total'));
      final upTotal = tester.getCenter(find.text('214 MB total'));
      expect(downTotal.dx, closeTo(down.dx, 0.01));
      expect(upTotal.dx, closeTo(up.dx, 0.01));
      expect(downTotal.dy, greaterThan(down.dy));
      expect(upTotal.dy, greaterThan(up.dy));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Download')),
        matchesSemantics(label: 'Download', value: '37 KB/s, 3.0 GB total'),
      );
      semantics.dispose();
    });

    testWidgets('clears previous session totals when inactive', (tester) async {
      await tester.pumpWidget(
        _host(
          child: MetricsStrip(
            uplink: 25600,
            downlink: 37888,
            session: const Duration(minutes: 12),
            uplinkTotal: 214 * 1024 * 1024,
            downlinkTotal: 3 * 1024 * 1024 * 1024,
            totalLabel: (value) => '$value total',
          ),
        ),
      );
      expect(find.text('0 B total'), findsNWidgets(2));
      expect(find.text('0 B/s'), findsNWidgets(2));
      expect(find.text('00:00:00'), findsOneWidget);
    });

    testWidgets('keeps large text readable and the clock centred on a phone', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _host(
          textScale: 2,
          child: MetricsStrip(
            uplink: 25600,
            downlink: 37888,
            session: const Duration(hours: 12, minutes: 47),
            isActive: true,
            uplinkLabel: 'Upload',
            sessionLabel: 'Time',
            downlinkLabel: 'Download',
            uplinkTotal: 214 * 1024 * 1024,
            downlinkTotal: 3 * 1024 * 1024 * 1024,
            totalLabel: (value) => '$value total',
          ),
        ),
      );
      final clock = tester.getCenter(find.text('12:47:00'));
      expect(
        clock.dx,
        closeTo(tester.getRect(find.byType(MetricsStrip)).center.dx, 0.01),
      );
      expect(tester.getCenter(find.text('37 KB/s')).dy, greaterThan(clock.dy));
      expect(tester.getCenter(find.text('25 KB/s')).dy, greaterThan(clock.dy));
      expect(find.text('3.0 GB total'), findsOneWidget);
      expect(find.text('214 MB total'), findsOneWidget);
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
      expect(ConnectState.stopping.isTransitional, isTrue);
      expect(ConnectState.connected.isTunnelUp, isTrue);
      expect(ConnectState.error.isTunnelUp, isFalse);
    });
  });
}
