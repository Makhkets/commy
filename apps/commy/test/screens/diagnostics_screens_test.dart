import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/i18n/translations_locale.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_core/commy_core.dart';
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

  /// Imports a link and connects through it, whatever the core makes of it.
  ///
  /// The listener is not optional. Nothing on this screen watches the node
  /// list, and a provider nobody listens to is disposed between reads, so the
  /// preview the controller builds after a connect came back null without it.
  Future<ProviderContainer> connectOnce(WidgetTester tester) async {
    const link = 'vless://11111111-2222-3333-4444-555555555555'
        '@nl-03.example.net:443?security=reality&type=tcp'
        '&pbk=xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k'
        '&sid=ab12cd34#Amsterdam%2003';
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
    return container;
  }

  /// Gets a real document onto the config tab: import a link, connect.
  Future<ProviderContainer> buildConfig(WidgetTester tester) async {
    final container = await connectOnce(tester);
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

  /// What the core says when it will not take a document. The UUID stands
  /// for any credential a complaint may quote, and must not reach the screen.
  const refusal = ConfigInvalidFailure(
    'outbounds[0]: uuid 11111111-2222-3333-4444-555555555555 is not allowed',
  );

  ErrorBanner banner(WidgetTester tester) =>
      tester.widget<ErrorBanner>(find.byType(ErrorBanner));

  // "Show the config" on a refused connect lands on this tab, which read the
  // last document that worked and nothing else. After a first connect it
  // said nothing had been built and pointed at the connect that had just
  // failed.
  testWidgets('config: a connect the core refused shows what it refused',
      (tester) async {
    await pump(tester, const ConfigScreen());
    harness.core.failOn(FakeCoreStep.start, refusal);

    final container = await connectOnce(tester);

    final state = container.read(tunnelControllerProvider);
    expect(state.failure, refusal);
    expect(state.configRefused, isTrue);
    expect(state.lastConfig, isNull, reason: 'nothing was accepted');
    expect(state.rejectedConfig, isNotNull);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(banner(tester).title, t.diagnostics.configRefused);
    expect(banner(tester).message, contains('outbounds[0]'));
    expect(
      banner(tester).message,
      isNot(contains('11111111-2222-3333-4444-555555555555')),
    );
    expect(find.text(t.diagnostics.configEmpty), findsNothing);
  });

  // After a refused reload the tunnel runs on, on the previous document. The
  // tab showed that one as if it were the answer to "show the config".
  testWidgets('config: a reload the core refused shows the refused document',
      (tester) async {
    // The status the fake core reports, not a pinned one: a reload only runs
    // on a tunnel that is up.
    await tester.pumpWidget(harness.wrap(const ConfigScreen()));
    await settle(tester);
    final status = ProviderScope.containerOf(
      tester.element(find.byType(ConfigScreen)),
      listen: false,
    ).listen(coreStatusProvider, (_, __) {});
    addTearDown(status.close);
    final container = await buildConfig(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final running = container.read(tunnelControllerProvider).lastConfig;
    harness.core.failOn(FakeCoreStep.reload, refusal);
    // A different document from the one running, so the test can tell
    // which of the two the tab shows.
    await container
        .read(settingsControllerProvider.notifier)
        .setLogLevel(LogLevel.debug);
    await settle(tester);

    final reloaded =
        await container.read(tunnelControllerProvider.notifier).reload();
    await settle(tester);

    expect(reloaded, isFalse);
    final state = container.read(tunnelControllerProvider);
    expect(state.lastConfig, same(running), reason: 'still the one running');
    expect(state.rejectedConfig, isNotNull);
    expect(state.rejectedConfig, isNot(running));
    expect(banner(tester).title, t.diagnostics.configRefused);

    harness.core.clearFailures();
    await stopTunnel(tester, container);
  });

  // ConfigInvalidFailure is also how the Clash API answers a switch to an
  // outbound it does not know, and its way out leads here all the same. The
  // tunnel is up on the document below and nothing refused it: a banner
  // saying no configuration could be built was a headline about something
  // that never happened.
  testWidgets('config: a switch the core turned away is not a refusal',
      (tester) async {
    await tester.pumpWidget(harness.wrap(const ConfigScreen()));
    await settle(tester);
    final status = ProviderScope.containerOf(
      tester.element(find.byType(ConfigScreen)),
      listen: false,
    ).listen(coreStatusProvider, (_, __) {});
    addTearDown(status.close);
    final container = await buildConfig(tester);
    await tester.pump(const Duration(milliseconds: 100));
    final running = container.read(tunnelControllerProvider).lastConfig;
    final node = container.read(nodesProvider).requireValue.single;
    const turnedAway = ConfigInvalidFailure('No such outbound or group');
    harness.core.failOn(FakeCoreStep.select, turnedAway);

    await container.read(tunnelControllerProvider.notifier).selectNode(node);
    await settle(tester);

    final state = container.read(tunnelControllerProvider);
    expect(state.failure, turnedAway);
    expect(state.configRefused, isFalse);
    expect(state.lastConfig, same(running));
    expect(find.byType(ErrorBanner), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);

    harness.core.clearFailures();
    await stopTunnel(tester, container);
  });

  // The other failure of that type with the tunnel up: a check whose probe
  // URL is not one. What runs is the document on the tab, and it is shown
  // as it was before the check, with no word about a build.
  testWidgets('config: a check with no probe URL leaves the running config',
      (tester) async {
    await pump(
      tester,
      const ConfigScreen(),
      extra: <Override>[
        tunnelControllerProvider.overrideWith(
          () => _PinnedTunnel(
            const TunnelActionState(
              failure: ConfigInvalidFailure(
                'Latency probe URL is not configured',
              ),
              lastConfig: CoreConfig(<String, Object?>{
                'log': <String, Object?>{'level': 'info'},
              }),
            ),
          ),
        ),
      ],
    );

    expect(find.byType(ErrorBanner), findsNothing);
    expect(find.byType(EmptyState), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('config: a document the builder refused says why',
      (tester) async {
    await pump(
      tester,
      const ConfigScreen(),
      extra: <Override>[
        tunnelControllerProvider.overrideWith(
          () => _PinnedTunnel(
            const TunnelActionState(
              failure: ConfigInvalidFailure(
                'REALITY public key must be 32 bytes',
              ),
              configRefused: true,
            ),
          ),
        ),
      ],
    );

    final empty = emptyState(tester);
    expect(empty.title, t.diagnostics.configNotBuilt);
    expect(empty.message, 'REALITY public key must be 32 bytes');
    expect(empty.actionLabel, t.error.openLogs);
    expect(empty.onAction, isNotNull);
  });

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

/// A tunnel controller frozen at [_state], so the tab can be drawn for a
/// failure no fake core produces.
class _PinnedTunnel extends TunnelController {
  _PinnedTunnel(this._state);

  final TunnelActionState _state;

  @override
  TunnelActionState build() => _state;
}
