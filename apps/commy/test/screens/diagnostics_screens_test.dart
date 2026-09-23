import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/i18n/translations_locale.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Lets a toast's own timer run out, so no pending timer fails the test.
  Future<void> expireToast(WidgetTester tester) async {
    await tester.pump(ToastMessenger.duration);
    await tester.pumpAndSettle();
  }

  Future<void> tapCopy(WidgetTester tester) async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is CommyIconButton && widget.icon == CommyIcons.copy,
      ),
    );
    await settle(tester);
  }

  Toast toast(WidgetTester tester) =>
      tester.widget<Toast>(find.byType(Toast).first);

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

    testWidgets('copying an empty log says so instead of claiming success',
        (tester) async {
      // The export of an empty ring buffer is an empty string, not a
      // failure, so the button used to write "" to the clipboard and report
      // "скопировано" — the user walks off believing they have the log.
      await pump(tester, const LogsScreen());

      await tapCopy(tester);

      expect(toast(tester).message, t.diagnostics.logsEmpty);
      expect(toast(tester).tone, CommyTone.neutral);
      expect(harness.clipboard.text, isNull, reason: 'nothing to copy');
      await expireToast(tester);
    });

    testWidgets('a clipboard that refuses is not reported as a success',
        (tester) async {
      // `write` returns a `Result` that this screen used to drop on the
      // floor, so a channel failure and a copy looked identical.
      await harness.logRepository.append(
        LogLine(
          level: LogLevel.info,
          message: 'inbound/tun: started',
          at: CommyTestHarness.now,
        ),
      );
      // A nested scope, not `extra`: Riverpod refuses the same provider
      // overridden twice in one container, and the harness pins the
      // clipboard already.
      await pump(
        tester,
        ProviderScope(
          overrides: <Override>[
            clipboardProvider.overrideWith((ref) => _DeadClipboard()),
          ],
          child: const LogsScreen(),
        ),
      );

      await tapCopy(tester);

      expect(toast(tester).tone, CommyTone.error);
      expect(toast(tester).message, isNot(t.diagnostics.copied));
      expect(toast(tester).message.trim(), isNotEmpty);
      await expireToast(tester);
    });

    testWidgets('a copy that works reports it through the shared toast',
        (tester) async {
      await harness.logRepository.append(
        LogLine(
          level: LogLevel.info,
          message: 'inbound/tun: started',
          at: CommyTestHarness.now,
        ),
      );
      await pump(tester, const LogsScreen());

      await tapCopy(tester);

      expect(toast(tester).message, t.diagnostics.copied);
      expect(harness.clipboard.text, contains('inbound/tun: started'));
      await expireToast(tester);
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

  /// Gets a real document onto the config tab: import a link, connect.
  ///
  /// The listener is not optional. Nothing on this screen watches the node
  /// list, and a provider nobody listens to is disposed between reads, so the
  /// preview the controller builds after a connect came back null without it.
  Future<ProviderContainer> buildConfig(WidgetTester tester) async {
    const link = 'vless://11111111-2222-3333-4444-555555555555'
        '@nl-03.example.net:443?security=reality&type=tcp'
        '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Amsterdam%2003';
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ConfigScreen)),
      listen: false,
    );
    final subscription = container.listen(nodesProvider, (_, __) {});
    addTearDown(subscription.close);
    final nodeId = await container
        .read(importControllerProvider.notifier)
        .importText(link);
    await settle(tester);
    await container
        .read(tunnelControllerProvider.notifier)
        .connect(nodeId: nodeId);
    await settle(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    return container;
  }

  /// Stops the tunnel the config was built from.
  ///
  /// The fake core ticks traffic every 50ms while it is up, and a widget test
  /// that ends with that timer alive fails on the pending timer rather than
  /// on its own assertions.
  Future<void> stopTunnel(WidgetTester tester, ProviderContainer c) async {
    await c.read(tunnelControllerProvider.notifier).disconnect();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  testWidgets('config: copying says it happened, and copies the redacted text',
      (tester) async {
    // The write was fire-and-forget with no message of any kind: the only
    // button on the tab looked exactly as broken when it worked as when it
    // failed. The second half of the assertion is rule R3 — what reaches the
    // clipboard is the redacted document, not the one with the UUID in it.
    await pump(tester, const ConfigScreen());
    final container = await buildConfig(tester);

    await tapCopy(tester);

    expect(toast(tester).message, t.diagnostics.copied);
    expect(harness.clipboard.text, contains('outbounds'));
    expect(
      harness.clipboard.text,
      isNot(contains('11111111-2222-3333-4444-555555555555')),
      reason: 'a copied config must not carry the credential',
    );
    await expireToast(tester);
    await stopTunnel(tester, container);
  });

  testWidgets('config: a clipboard that refuses is reported, not swallowed',
      (tester) async {
    await pump(
      tester,
      ProviderScope(
        overrides: <Override>[
          clipboardProvider.overrideWith((ref) => _DeadClipboard()),
        ],
        child: const ConfigScreen(),
      ),
    );
    final container = await buildConfig(tester);

    await tapCopy(tester);

    expect(toast(tester).tone, CommyTone.error);
    expect(toast(tester).message, isNot(t.diagnostics.copied));
    await expireToast(tester);
    await stopTunnel(tester, container);
  });

  testWidgets('stats: no samples yet points at the connect button',
      (tester) async {
    await pump(tester, const StatsScreen());

    final empty = emptyState(tester);
    expect(empty.actionLabel, t.diagnostics.goConnect);
    expect(empty.onAction, isNotNull);
  });

  testWidgets('stats: a recorded day is shown without a live tunnel',
      (tester) async {
    final now = CommyTestHarness.now;
    final withDays = CommyTestHarness(
      trafficDays: <TrafficDay>[
        TrafficDay(
          day: DateTime(now.year, now.month, now.day),
          scope: TrafficDay.allScope,
          upBytes: 1024,
          downBytes: 4096,
        ),
      ],
    );
    addTearDown(withDays.dispose);

    await tester.pumpWidget(
      withDays.wrap(const StatsScreen(), status: const TunnelStatus.idle()),
    );
    await settle(tester);

    expect(find.byType(EmptyState), findsNothing);
    // Section labels are drawn in capitals.
    expect(find.text(t.diagnostics.statsDays.toUpperCase()), findsOneWidget);
    expect(
      find.text(CommyByteFormat.bytes(5120, locale: t.flutterLocale)),
      findsOneWidget,
    );
    // The live sections have nothing to say with the tunnel down.
    expect(find.text(t.diagnostics.statsWindow), findsNothing);
  });
}

/// A clipboard the platform channel refuses to write to.
class _DeadClipboard implements ClipboardPort {
  @override
  Future<Result<String?, CommyFailure>> read() async =>
      const Ok<String?, CommyFailure>(null);

  @override
  Future<Result<void, CommyFailure>> write(String value) async =>
      const Err<void, CommyFailure>(
        StorageFailure('clipboard channel unavailable'),
      );
}
