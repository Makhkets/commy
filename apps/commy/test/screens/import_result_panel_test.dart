import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/commy_test_app.dart';

/// Queue item #16. This panel is the only report an import ever produces: it
/// is shown once, the user closes it, and there is no import history to go
/// back to. Whatever it fails to say is lost.
///
/// So what is protected here is the reporting itself. The count on screen is
/// the count that reached the repository. A line that was dropped is named
/// together with the reason it was dropped, because "2 skipped" tells a user
/// nothing they can act on. Nothing parsed does not render as something
/// parsed. A failure carries a cause, the action that failure itself declares
/// — not one guessed from `retryable` — and a route to the logs where that
/// action does not already go there, and leaving the report clears it so the
/// next import does not open on the last one. And the line that failed to
/// parse still holds a UUID or a password, so what the list of reasons shows
/// is the redacted form (rule R3).
void main() {
  final t = Translations();

  const publicKey = 'aGVsbG8td29ybGQtcHVibGljLWtleQ';
  const amsterdam = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=$publicKey&sid=ab12cd34#Amsterdam%2003';
  const warsaw = 'vless://22222222-3333-4444-5555-666666666666'
      '@pl-10.example.net:443?security=reality&type=tcp'
      '&pbk=$publicKey&sid=ef56ab78#Warsaw%2010';
  const oslo = 'vless://33333333-4444-5555-6666-777777777777'
      '@no-01.example.net:443?security=reality&type=tcp'
      '&pbk=$publicKey&sid=12ab34cd#Oslo%2001';

  /// The Amsterdam server again, under the name a panel renamed it to.
  ///
  /// Same protocol, address, port and credential — everything a node's
  /// identity is made of. The display name is deliberately left out of it, so
  /// this is one server, not two.
  const amsterdamRenamed = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=$publicKey&sid=ab12cd34#Amsterdam%2003%20backup';

  /// A line the parser has to refuse that still carries a credential.
  const brokenUuid = '44444444-5555-6666-7777-888888888888';
  const portless = 'vless://$brokenUuid@se-02.example.net#Stockholm%2002';

  /// A line that is not a link at all, for the other half of a partial import.
  const junk = 'a shopping list, copied by accident';

  const panelUrl = 'https://panel.example.net/sub/token';

  late CommyTestHarness harness;

  /// The diagnostics tabs as bare pages, so a destination is one `find.text`.
  ///
  /// Pumping the real screens would make a test about where a button goes fail
  /// for reasons inside the log view.
  GoRouter diagnosticsRouter() {
    return GoRouter(
      initialLocation: AppRoutes.home,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const Scaffold(),
        ),
        for (final tab in AppRoutes.diagnosticsTabs)
          GoRoute(
            path: tab,
            builder: (context, state) => Scaffold(body: Text(tab)),
          ),
      ],
    );
  }

  /// Stands the panel up on a route above a page, the way a sheet hosts it.
  ///
  /// The panel closes itself with `Navigator.pop`, so a panel pumped as the
  /// only route would have nowhere to pop to and the close buttons could not
  /// be tested at all.
  ///
  /// [parked] pins the controller on a result instead of running an import,
  /// for the states no real input can produce on demand. [routed] swaps the
  /// harness's plain `MaterialApp` for one with a router, which the branches
  /// whose button navigates need: a label alone does not say where a button
  /// lands, and landing on the wrong diagnostics tab is what this panel used
  /// to do.
  Future<void> pumpPanel(
    WidgetTester tester, {
    ImportState? parked,
    bool routed = false,
  }) async {
    // Taller than the 800x600 default: the success panel with its skipped
    // lines expanded does not fit, and a surface that clipped them would be
    // testing the window rather than the panel.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);

    final overrides = <Override>[
      if (parked != null)
        importControllerProvider.overrideWith(
          () => _ParkedImportController(parked),
        ),
    ];

    if (routed) {
      final router = diagnosticsRouter();
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: harness.overrides(extra: overrides),
          child: TranslationProvider(
            child: Builder(
              builder: (context) => MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: CommyTheme.dark,
                locale: TranslationProvider.of(context).flutterLocale,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                routerConfig: router,
              ),
            ),
          ),
        ),
      );
    } else {
      await tester.pumpWidget(harness.wrap(const Scaffold(), extra: overrides));
    }
    await tester.pumpAndSettle();

    unawaited(
      Navigator.of(tester.element(find.byType(Scaffold))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(
            body: SingleChildScrollView(child: ImportResultPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer scope(WidgetTester tester) => ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );

  ImportState importState(WidgetTester tester) =>
      scope(tester).read(importControllerProvider);

  /// Runs the shipping paste path, not a hand-built result.
  Future<void> importText(WidgetTester tester, String input) async {
    await scope(tester)
        .read(importControllerProvider.notifier)
        .importText(input);
    await tester.pumpAndSettle();
  }

  /// Runs the shipping subscription path, which owns the retryable failure.
  Future<void> addSubscription(WidgetTester tester) async {
    await scope(tester).read(importControllerProvider.notifier).addSubscription(
          url: Uri.parse(panelUrl),
        );
    await tester.pumpAndSettle();
  }

  List<ProxyNode> stored() => harness.nodeRepository.nodes;

  /// Every string the panel actually put on screen.
  List<String> rendered(WidgetTester tester) => <String>[
        for (final text in tester.widgetList<Text>(find.byType(Text)))
          text.data ?? text.textSpan?.toPlainText() ?? '',
      ];

  testWidgets('the count it reports is the count that reached the library',
      (tester) async {
    await pumpPanel(tester);

    await importText(tester, '$amsterdam\n$warsaw\n$oslo');

    expect(find.text(t.import.result.imported(count: 3)), findsOneWidget);
    // The number on screen means nothing on its own: what makes it true is
    // that three servers are in the repository behind it.
    expect(stored(), hasLength(3));
    // A clean import has nothing to expand, so the toggle is not offered.
    expect(find.text(t.import.result.showSkipped), findsNothing);
  });

  testWidgets('the same server under two names is reported once',
      (tester) async {
    // The over-count this panel used to show: two links that name one server
    // collapse into one row on upsert, and the count came off the parser,
    // which had counted lines. Nothing corrects it afterwards — the panel is
    // the only report an import produces.
    await pumpPanel(tester);

    await importText(tester, '$amsterdam\n$amsterdamRenamed');

    expect(stored(), hasLength(1));
    expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);
    expect(find.text(t.import.result.imported(count: 2)), findsNothing);
    // And a duplicate is not a broken line: the skipped section names lines
    // the parser refused, and it refused neither of these.
    expect(importState(tester).outcome!.failures, isEmpty);
    expect(find.text(t.import.result.showSkipped), findsNothing);
  });

  testWidgets('a partial import reports both halves', (tester) async {
    await pumpPanel(tester);

    await importText(tester, '$amsterdam\n$junk\n$warsaw\n$portless');

    expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);
    expect(find.text(t.import.result.skipped(count: 2)), findsOneWidget);
    expect(
      stored().map((node) => node.host),
      <String>['nl-03.example.net', 'pl-10.example.net'],
    );
  });

  testWidgets('every skipped line is named, with the reason it was skipped',
      (tester) async {
    await pumpPanel(tester);
    await importText(tester, '$amsterdam\n$junk\n$portless');

    final failures = importState(tester).outcome!.failures;
    expect(failures, hasLength(2));
    // Collapsed to start with: the reasons are asked for, not thrown at the
    // user.
    for (final failure in failures) {
      expect(find.text(failure.reason), findsNothing);
    }

    await tester.tap(find.text(t.import.result.showSkipped));
    await tester.pumpAndSettle();

    // Two lines were dropped for two different reasons, and a user told only
    // "2 skipped" cannot fix either of them.
    for (final failure in failures) {
      expect(find.text(failure.reason), findsOneWidget);
      expect(find.text(failure.redactedLine), findsOneWidget);
    }
  });

  testWidgets('a line that failed to parse does not show its credential',
      (tester) async {
    await pumpPanel(tester);
    await importText(tester, '$amsterdam\n$portless');

    await tester.tap(find.text(t.import.result.showSkipped));
    await tester.pumpAndSettle();

    // The redacted form keeps the host and the name — which is what makes the
    // line recognisable — and drops the user id in front of them.
    expect(find.text(Redact.link(portless)), findsOneWidget);
    expect(
      rendered(tester).where((line) => line.contains(brokenUuid)),
      isEmpty,
      reason: 'a credential from a skipped line reached the screen',
    );
  });

  testWidgets('nothing found is not the same panel as something found',
      (tester) async {
    await pumpPanel(
      tester,
      parked: const ImportState(outcome: ParseOutcome.empty),
    );

    expect(find.text(t.import.result.nothing), findsOneWidget);
    // An empty state without a next step is half a state: it says what a
    // parseable input looks like, and it offers the way out.
    expect(find.text(t.import.result.nothingBody), findsOneWidget);
    expect(find.text(t.common.close), findsOneWidget);
    // And it is not the success panel with a zero in it.
    expect(find.text(t.import.result.imported(count: 0)), findsNothing);
    expect(find.text(t.common.done), findsNothing);
  });

  testWidgets('closing an empty result clears it', (tester) async {
    await pumpPanel(
      tester,
      parked: const ImportState(outcome: ParseOutcome.empty),
    );
    final container = scope(tester);

    await tester.tap(find.text(t.common.close));
    await tester.pumpAndSettle();

    // A result left in the controller is a result the next open of the sheet
    // would show instead of the import options.
    expect(container.read(importControllerProvider), ImportState.idle);
    expect(find.byType(ImportResultPanel), findsNothing);
  });

  testWidgets('done clears the report and keeps what was imported',
      (tester) async {
    await pumpPanel(tester);
    await importText(tester, amsterdam);
    final container = scope(tester);

    await tester.tap(find.text(t.common.done));
    await tester.pumpAndSettle();

    expect(container.read(importControllerProvider), ImportState.idle);
    expect(find.byType(ImportResultPanel), findsNothing);
    // Closing the report is not undoing the import.
    expect(stored(), hasLength(1));
  });

  testWidgets('a write the library refused is not reported as an import',
      (tester) async {
    // The count on the success panel comes from the parser, and the parser
    // never touched the database. Two links parse cleanly here and the store
    // still refuses them, which is the one case where "parsed" and "imported"
    // come apart far enough to be worth a screen of its own.
    await pumpPanel(tester);
    harness.nodeRepository.failure = const StorageFailure('database is locked');

    await importText(tester, '$amsterdam\n$warsaw');

    expect(stored(), isEmpty);
    expect(find.text(t.import.result.imported(count: 2)), findsNothing);
    expect(find.text(t.common.done), findsNothing);
    // And it says which of the two things went wrong: a full disk is not a
    // broken link, and the user can do something about one of them.
    expect(find.text(t.error.storage.message), findsOneWidget);
    expect(find.text(t.error.openLogs), findsOneWidget);
  });

  group('the failure panel', () {
    testWidgets('states a cause and leaves a route to the logs',
        (tester) async {
      await pumpPanel(tester);

      await importText(tester, junk);

      expect(importState(tester).failure, isA<SubscriptionMalformedFailure>());
      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text(t.error.title), findsOneWidget);
      expect(find.text(t.error.subscriptionMalformed.message), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
      // A failure is not a success with a zero in it, and it stored nothing.
      expect(find.text(t.import.result.imported(count: 0)), findsNothing);
      expect(stored(), isEmpty);
    });

    testWidgets('a failure that opens the logs gets one button, not two',
        (tester) async {
      await pumpPanel(tester);

      await importText(tester, junk);

      // `subscription_malformed` declares `openLogs` as its own action, so the
      // ghost link under the button would be a second button to the same
      // screen — noise, not a second way out.
      expect(importState(tester).failure, isA<SubscriptionMalformedFailure>());
      expect(find.byType(CommyButton), findsOneWidget);
      expect(
        find.widgetWithText(CommyButton, t.error.subscriptionMalformed.action),
        findsOneWidget,
      );
      // And a call that cannot be repeated is not told to repeat itself.
      expect(importState(tester).failure?.retryable, isFalse);
      expect(find.text(t.common.retry), findsNothing);
    });

    testWidgets('a storage failure is offered the retry it declares',
        (tester) async {
      // The panel used to label this button off `retryable`, which `storage`
      // answers false, while the failure's own action is a retry: a write that
      // failed on a locked database was offered "close" and nothing else.
      await pumpPanel(tester);
      harness.nodeRepository.failure =
          const StorageFailure('database is locked');

      await importText(tester, amsterdam);

      expect(importState(tester).failure, isA<StorageFailure>());
      expect(
        find.widgetWithText(CommyButton, t.error.storage.action),
        findsOneWidget,
      );
      expect(find.text(t.common.close), findsNothing);
      // `storage` does not go to diagnostics itself, so the way there stays.
      expect(
        find.widgetWithText(CommyButton, t.error.openLogs),
        findsOneWidget,
      );

      await tester.tap(find.text(t.error.storage.action));
      await tester.pumpAndSettle();

      // A retry hands the sheet back what was typed; it does not close it,
      // which is what the old "close" button did to this very failure.
      expect(scope(tester).read(importControllerProvider), ImportState.idle);
      expect(find.byType(ImportResultPanel), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);
    });

    testWidgets('a config failure opens the config, not the logs',
        (tester) async {
      // The one action that is neither a retry nor the log tab. A panel that
      // sent every button to the logs showed exactly this label and still
      // landed on the wrong screen, which no label assertion would catch.
      await pumpPanel(
        tester,
        parked: const ImportState(
          failure: ConfigInvalidFailure('no outbound named proxy'),
        ),
        routed: true,
      );

      expect(
        find.widgetWithText(CommyButton, t.error.configInvalid.action),
        findsOneWidget,
      );
      // Its action goes elsewhere, so the quieter route to the logs stays.
      expect(
        find.widgetWithText(CommyButton, t.error.openLogs),
        findsOneWidget,
      );

      await tester.tap(find.text(t.error.configInvalid.action));
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.diagnosticsConfig), findsOneWidget);
      expect(find.text(AppRoutes.diagnosticsLogs), findsNothing);
    });

    testWidgets('offers retry when repeating the call can help',
        (tester) async {
      await pumpPanel(tester);
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse(panelUrl),
        cause: 'connection refused',
      );

      await addSubscription(tester);

      expect(importState(tester).failure?.retryable, isTrue);
      expect(
        find.text(t.error.subscriptionUnreachable.message),
        findsOneWidget,
      );
      expect(find.text(t.common.retry), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
    });

    testWidgets('retry clears the failure without closing the sheet',
        (tester) async {
      // docs/05-ux-flows.md, scenario 1: the sheet stays open and what was
      // entered is not lost. Popping here would throw away the URL the user
      // typed, which is the one thing a retry needs.
      await pumpPanel(tester);
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse(panelUrl),
        cause: 'connection refused',
      );
      await addSubscription(tester);
      final container = scope(tester);

      await tester.tap(find.text(t.common.retry));
      await tester.pumpAndSettle();

      expect(container.read(importControllerProvider), ImportState.idle);
      expect(find.byType(ImportResultPanel), findsOneWidget);
      // The panel is still mounted, so the sheet was not popped — and the
      // error is gone from it, which is what says the clear reached the UI
      // and not only the controller.
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text(t.error.subscriptionUnreachable.message), findsNothing);
    });

    testWidgets('leaving for the logs clears the result and the sheet',
        (tester) async {
      await pumpPanel(tester, routed: true);
      await importText(tester, junk);
      final container = scope(tester);

      await tester.tap(find.text(t.error.subscriptionMalformed.action));
      await tester.pumpAndSettle();

      expect(find.text(AppRoutes.diagnosticsLogs), findsOneWidget);
      // A sheet left open would sit on top of the tab it just opened, and a
      // result left on the controller is what the next open of the sheet would
      // show instead of the import options.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(container.read(importControllerProvider), ImportState.idle);
    });
  });
}

/// The shipping controller, parked on a result the test picked.
///
/// Used only for the states no real input produces on demand; everything the
/// panel then calls on it — `reset` above all — is the shipping behaviour.
class _ParkedImportController extends ImportController {
  _ParkedImportController(this._parked);

  final ImportState _parked;

  @override
  ImportState build() => _parked;
}
