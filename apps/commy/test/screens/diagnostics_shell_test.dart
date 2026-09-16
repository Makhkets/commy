import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The frame the four diagnostics tabs share.
///
/// The tabs are four independent routes rather than a `TabBarView`, which
/// means nothing in the widget tree forces them to agree: each screen names
/// its own tab, and a screen that named the wrong one — or forgot the frame
/// altogether — would still build, still render, and quietly mark the wrong
/// segment. So these tests pin the two halves of that agreement: the segments
/// are exactly the routes the router knows, and every tab claims itself.
///
/// The body assertions are deliberately negative as well. Four routes means
/// exactly one tab is alive at a time; a shell that rebuilt the others into
/// existence would run four log listeners and four connection streams behind
/// one visible screen.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  setUp(() => harness = CommyTestHarness());
  tearDown(() => harness.dispose());

  /// The core only snapshots connections while it runs; pinning the stream is
  /// how this test gets a settled screen rather than a skeleton that never
  /// resolves.
  Override noConnections() => connectionsProvider.overrideWith(
        (ref) => Stream<List<ConnectionInfo>>.value(const <ConnectionInfo>[]),
      );

  final tabs = <({String route, String label, Widget screen, Type type})>[
    (
      route: AppRoutes.diagnosticsLogs,
      label: t.diagnostics.logs,
      screen: const LogsScreen(),
      type: LogsScreen,
    ),
    (
      route: AppRoutes.diagnosticsConnections,
      label: t.diagnostics.connections,
      screen: const ConnectionsScreen(),
      type: ConnectionsScreen,
    ),
    (
      route: AppRoutes.diagnosticsConfig,
      label: t.diagnostics.config,
      screen: const ConfigScreen(),
      type: ConfigScreen,
    ),
    (
      route: AppRoutes.diagnosticsStats,
      label: t.diagnostics.stats,
      screen: const StatsScreen(),
      type: StatsScreen,
    ),
  ];

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    List<Override> extra = const <Override>[],
  }) async {
    await tester.pumpWidget(harness.wrap(screen, extra: extra));
    await settle(tester);
  }

  SegmentedControl<String> control(WidgetTester tester) =>
      tester.widget<SegmentedControl<String>>(
        find.byType(SegmentedControl<String>),
      );

  /// Whether the segment carrying [label] is announced as the selected one.
  ///
  /// Read off the rendered semantics rather than off the control's value:
  /// the mark is what tells a screen reader which tab it is on, and a
  /// segment that lost it would still hold the right value.
  bool isMarked(WidgetTester tester, String label) {
    final semantics = tester.widget<Semantics>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Semantics))
          .first,
    );
    return semantics.properties.selected ?? false;
  }

  testWidgets('the segments are the four tab routes, in order', (tester) async {
    await pumpScreen(
      tester,
      const DiagnosticsShell(
        route: AppRoutes.diagnosticsLogs,
        child: SizedBox.shrink(),
      ),
    );

    // A segment whose value is not a route the router serves is a dead tab:
    // the tap navigates, go_router matches nothing, and the user is left on
    // the screen they tried to leave.
    expect(
      control(tester).segments.map((segment) => segment.value).toList(),
      AppRoutes.diagnosticsTabs,
    );
    expect(
      control(tester).segments.map((segment) => segment.label).toList(),
      <String>[
        t.diagnostics.logs,
        t.diagnostics.connections,
        t.diagnostics.config,
        t.diagnostics.stats,
      ],
    );
  });

  testWidgets('the frame names the section and keeps the way back',
      (tester) async {
    await pumpScreen(
      tester,
      const DiagnosticsShell(
        route: AppRoutes.diagnosticsLogs,
        child: Text(_bodyMarker),
      ),
    );

    expect(find.text(t.diagnostics.title), findsOneWidget);
    expect(find.text(_bodyMarker), findsOneWidget);

    final bar = tester.widget<CommyAppBar>(find.byType(CommyAppBar));
    // A bare chevron with no label says nothing to a screen reader.
    expect(bar.backSemanticLabel, t.a11y.back);

    // Diagnostics is opened from settings and has to lead back there. It has
    // no bottom bar and is not a root route, so an arrow wired to an empty
    // closure — which `isNotNull` would happily accept — strands the user.
    await tester.tap(find.byIcon(CommyIcons.chevronLeft));
    await settle(tester);
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('GoRouter'),
      ),
      reason: '${AppRoutes.settings} has to be handed to the router',
    );
  });

  testWidgets("a tab's own actions reach the app bar", (tester) async {
    const copyKey = ValueKey<String>('copy');
    await pumpScreen(
      tester,
      DiagnosticsShell(
        route: AppRoutes.diagnosticsConfig,
        actions: <Widget>[
          CommyIconButton(
            key: copyKey,
            icon: CommyIcons.copy,
            semanticLabel: t.diagnostics.copy,
            onPressed: () {},
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );

    // The config tab's copy button is the only control any tab contributes,
    // and it is worthless anywhere but the bar.
    expect(
      find.descendant(
        of: find.byType(CommyAppBar),
        matching: find.byKey(copyKey),
      ),
      findsOneWidget,
    );
  });

  for (final tab in tabs) {
    testWidgets('${tab.type} claims its own tab and nothing else builds',
        (tester) async {
      await pumpScreen(
        tester,
        tab.screen,
        extra: <Override>[if (tab.type == ConnectionsScreen) noConnections()],
      );

      // A tab that forgot the frame would lose the way back and the other
      // three tabs with it.
      expect(find.byType(DiagnosticsShell), findsOneWidget);
      expect(control(tester).value, tab.route);

      for (final other in tabs) {
        expect(
          find.byType(other.type),
          other.route == tab.route ? findsOneWidget : findsNothing,
          reason: 'only ${tab.type} belongs on ${tab.route}',
        );
      }
    });
  }

  testWidgets('exactly one segment is marked, and it is the live one',
      (tester) async {
    await pumpScreen(tester, const ConfigScreen());

    expect(isMarked(tester, t.diagnostics.config), isTrue);
    expect(isMarked(tester, t.diagnostics.logs), isFalse);
    expect(isMarked(tester, t.diagnostics.connections), isFalse);
    expect(isMarked(tester, t.diagnostics.stats), isFalse);
  });

  testWidgets('a segment hands its route to the router, except the live one',
      (tester) async {
    await pumpScreen(
      tester,
      const DiagnosticsShell(
        route: AppRoutes.diagnosticsStats,
        child: SizedBox.shrink(),
      ),
    );

    // The harness stands no router up on purpose, and that is what tells the
    // two halves apart. Tapping the tab already on screen has to do nothing:
    // the control calls back on every segment, selected or not, so the shell
    // comparing the chosen value with the current one is the only reason a
    // tab does not reload itself under the finger.
    await tester.tap(find.text(t.diagnostics.stats));
    await settle(tester);
    expect(tester.takeException(), isNull);
    expect(control(tester).value, AppRoutes.diagnosticsStats);

    // Every other segment has to reach the router. Without this half a shell
    // that navigated nowhere at all would pass every test in this file: four
    // dead tabs that still highlight the right one.
    await tester.tap(find.text(t.diagnostics.logs));
    await settle(tester);
    expect(
      tester.takeException(),
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('GoRouter'),
      ),
      reason: '${AppRoutes.diagnosticsLogs} has to be handed over, not held',
    );
  });
}

/// Stands in for a tab body, so the frame can be tested without one.
const String _bodyMarker = 'tab body';
