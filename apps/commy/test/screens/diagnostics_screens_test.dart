import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The four diagnostics tabs with nothing to show.
///
/// docs/05-ux-flows.md: an empty state is an icon, an explanation and an
/// action — "no data" alone is not one. These tests pin the action, because
/// the action is the half that used to be missing on every one of them.
void main() {
  late CommyTestHarness harness;
  final t = Translations();

  setUp(() => harness = CommyTestHarness());
  tearDown(() => harness.dispose());

  EmptyState emptyState(WidgetTester tester) =>
      tester.widget<EmptyState>(find.byType(EmptyState));

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    TunnelStatus status = const TunnelStatus.idle(),
    List<Override> extra = const <Override>[],
  }) async {
    await tester.pumpWidget(harness.wrap(screen, status: status, extra: extra));
    await settle(tester);
  }

  /// The fake core only snapshots connections while it runs; pinning the
  /// stream is how a test gets an empty list rather than a skeleton.
  Override noConnections() => connectionsProvider.overrideWith(
        (ref) => Stream<List<ConnectionInfo>>.value(const <ConnectionInfo>[]),
      );

  group('logs', () {
    testWidgets('with nothing written, the way out is the connect button',
        (tester) async {
      await pump(tester, const LogsScreen());

      final empty = emptyState(tester);
      expect(empty.actionLabel, t.diagnostics.goConnect);
      expect(empty.onAction, isNotNull);
    });

    testWidgets('a filter that matches nothing is undone on this screen',
        (tester) async {
      await harness.logRepository.append(
        LogLine(
          level: LogLevel.info,
          message: 'inbound/tun: started',
          at: CommyTestHarness.now,
        ),
      );
      await pump(tester, const LogsScreen());
      expect(find.byType(EmptyState), findsNothing);

      await tester.enterText(find.byType(TextField), 'no such line');
      await settle(tester);

      final empty = emptyState(tester);
      expect(empty.actionLabel, t.diagnostics.resetFilters);
      expect(find.text(t.diagnostics.logsFiltered), findsOneWidget);

      await tester.tap(find.text(t.diagnostics.resetFilters));
      await settle(tester);

      expect(find.byType(EmptyState), findsNothing);
    });
  });

  group('connections', () {
    testWidgets('with the tunnel down, the way out is the connect button',
        (tester) async {
      await pump(
        tester,
        const ConnectionsScreen(),
        extra: <Override>[noConnections()],
      );

      final empty = emptyState(tester);
      expect(empty.actionLabel, t.diagnostics.goConnect);
      expect(empty.onAction, isNotNull);
    });

    testWidgets('with the tunnel up, the action asks the core again',
        (tester) async {
      await pump(
        tester,
        const ConnectionsScreen(),
        status: TunnelStatus.connected(since: CommyTestHarness.now),
        extra: <Override>[noConnections()],
      );

      expect(emptyState(tester).actionLabel, t.diagnostics.refresh);

      await tester.tap(find.text(t.diagnostics.refresh));
      await settle(tester);

      // Still nothing to show, and still a way out — not a skeleton.
      expect(emptyState(tester).actionLabel, t.diagnostics.refresh);
    });
  });

  testWidgets('config: nothing built yet points at the connect button',
      (tester) async {
    await pump(tester, const ConfigScreen());

    final empty = emptyState(tester);
    expect(empty.actionLabel, t.diagnostics.goConnect);
    expect(empty.onAction, isNotNull);
  });

  testWidgets('stats: no samples yet points at the connect button',
      (tester) async {
    await pump(tester, const StatsScreen());

    final empty = emptyState(tester);
    expect(empty.actionLabel, t.diagnostics.goConnect);
    expect(empty.onAction, isNotNull);
  });
}
