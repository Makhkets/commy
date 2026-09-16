import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/screens/import/subscription_sheet.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Adding a subscription by URL — the one import path that talks to a host the
/// user typed, so it is the one where a mistake costs a request.
///
/// Four things are worth protecting here: the scheme guard refuses what no
/// client could fetch *before* anything leaves the device; a good URL ends
/// with the subscription and its servers both stored and joined by the
/// subscription id; the fetch goes around the tunnel, because the first one
/// after a reinstall has no tunnel to go through; and a panel that refuses to
/// answer leaves no half-imported row behind, while one that answers with a
/// broken line among good ones loses only that line. Every assertion reads the
/// fakes back rather than looking at the widget that drew the value.
///
/// And one thing about the sheet rather than the subscription: it is pushed
/// from the import sheet and from the first-run view, neither of which clears
/// the import state the way the `+` button does, so what it leaves behind when
/// it is dismissed by a gesture is what the next sheet opens on. A download is
/// the one import slow enough to still be running when that gesture happens,
/// which is why the sheet dragged away mid-fetch is tested here and not in the
/// import sheet's own file.
void main() {
  final t = Translations();

  const uuid = '11111111-2222-3333-4444-555555555555';
  const amsterdam = 'vless://$uuid@nl-03.example.net:443'
      '?security=reality&type=tcp'
      '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Amsterdam%2003';
  const warsaw = 'vless://99999999-8888-7777-6666-555555555555'
      '@pl-01.example.net:443?security=reality&type=tcp'
      '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Warsaw%2001';
  const body = '$amsterdam\n$warsaw';

  const panelUrl = 'https://panel.example.net/sub/token';

  /// The control that stands in for the import sheet or the first-run view.
  const openLabel = 'open the sheet';

  late CommyTestHarness harness;

  /// Stands the sheet body up on its own, the way `CommySheet` hosts it.
  ///
  /// [fetcher] is wired in through the use case rather than through
  /// `subscriptionFetcherProvider`: the harness already overrides that one,
  /// and Riverpod refuses a second override of the same provider in a
  /// container. Everything above the use case — the sheet, the controller and
  /// the repositories it writes to — is still the shipping wiring.
  Future<void> pumpScreen(
    WidgetTester tester, {
    String document = body,
    _ScriptedFetcher? fetcher,
  }) async {
    // Taller than the 800x600 default: two fields, the interval row, the
    // switch and the button, at phone width.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);
    harness.subscriptionFetcher.body = document;

    await tester.pumpWidget(
      harness.wrap(
        const Scaffold(
          body: SingleChildScrollView(child: SubscriptionSheet()),
        ),
        extra: <Override>[
          if (fetcher != null)
            addSubscriptionUseCaseProvider.overrideWithValue(
              AddSubscriptionUseCase(
                fetcher: fetcher,
                parser: CommyLinkParser(),
                subscriptions: harness.subscriptionRepository,
                nodes: harness.nodeRepository,
                ids: RandomIdGenerator(),
              ),
            ),
        ],
      ),
    );
    await settle(tester);
  }

  /// Stands the sheet up behind a button, on a route, the way it is opened.
  ///
  /// [pumpScreen] pumps the body alone, which is enough for everything about
  /// the form but says nothing about the route: only a real one can be
  /// dismissed by a gesture instead of by the panel's buttons.
  ///
  /// [fetcher] is wired in the same way [pumpScreen] wires it, and for the
  /// same reason: a download the test holds open is the only way to be inside
  /// the seconds a real one takes.
  Future<void> pumpEntryPoint(
    WidgetTester tester, {
    _ScriptedFetcher? fetcher,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);
    harness.subscriptionFetcher.body = body;

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(SubscriptionSheet.show(context)),
              child: const Text(openLabel),
            ),
          ),
        ),
        extra: <Override>[
          if (fetcher != null)
            addSubscriptionUseCaseProvider.overrideWithValue(
              AddSubscriptionUseCase(
                fetcher: fetcher,
                parser: CommyLinkParser(),
                subscriptions: harness.subscriptionRepository,
                nodes: harness.nodeRepository,
                ids: RandomIdGenerator(),
              ),
            ),
        ],
      ),
    );
    await settle(tester);
  }

  /// Drags the sheet off the bottom of the screen, by its handle.
  ///
  /// The handle is drawn because the sheet is dismissible, so this is a way
  /// out the user is being offered — and it goes nowhere near the buttons on
  /// the result panel.
  Future<void> dragSheetAway(WidgetTester tester) async {
    await tester.drag(find.byType(CommySheetSurface), const Offset(0, 600));
    await tester.pumpAndSettle();
  }

  Finder fieldWithLabel(String label) => find.byWidgetPredicate(
        (widget) => widget is CommyTextField && widget.labelText == label,
      );

  Finder addButton() =>
      find.widgetWithText(CommyButton, t.import.subscription.add);

  Future<void> submit(WidgetTester tester, String url, {String? name}) async {
    await tester.enterText(fieldWithLabel(t.import.subscription.url), url);
    if (name != null) {
      await tester.enterText(fieldWithLabel(t.import.subscription.name), name);
    }
    await tester.tap(addButton());
    await tester.pumpAndSettle();
  }

  Subscription stored() => harness.subscriptionRepository.items.single;

  testWidgets('a good URL stores the subscription and its servers',
      (tester) async {
    await pumpScreen(tester);

    await submit(tester, panelUrl);

    // The request went to exactly what was typed, once.
    expect(harness.subscriptionFetcher.requests, <Uri>[Uri.parse(panelUrl)]);
    expect(stored().url, Uri.parse(panelUrl));
    // The switch starts on, so the panel is refreshed on a timer from now on.
    expect(stored().autoUpdate, isTrue);

    final nodes = harness.nodeRepository.nodes;
    expect(nodes.map((node) => node.name), <String>[
      'Amsterdam 03',
      'Warsaw 01',
    ]);
    // Orphaned servers would never be refreshed with the panel, nor removed
    // with it.
    expect(
      nodes.every((node) => node.subscriptionId == stored().id),
      isTrue,
    );
    expect(
      find.text(t.import.result.imported(count: nodes.length)),
      findsOneWidget,
    );
  });

  testWidgets('one unreadable line does not sink the rest of the panel',
      (tester) async {
    // A panel that added an `ssr://` line last week must not cost the user
    // every server on it: the parser's contract is nodes plus reasons, and
    // the subscription path has to keep both halves.
    await pumpScreen(
      tester,
      document: '$amsterdam\nssr://Zm9v#Kyiv 01\n$warsaw',
    );

    await submit(tester, panelUrl);

    expect(harness.nodeRepository.nodes.map((node) => node.name), <String>[
      'Amsterdam 03',
      'Warsaw 01',
    ]);
    expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);
    // And the one that was dropped is counted rather than disappearing.
    expect(find.text(t.import.result.skipped(count: 1)), findsOneWidget);
  });

  testWidgets('the panel is asked directly, never through the tunnel',
      (tester) async {
    // docs/05-ux-flows.md, scenario 3: the first fetch after a reinstall has
    // no tunnel to route through — there is no server stored yet. A fetch
    // that went through one could never bring the first one in.
    final fetcher = _ScriptedFetcher(
      payload: const SubscriptionPayload(body: body),
    );
    await pumpScreen(tester, fetcher: fetcher);

    await submit(tester, panelUrl);

    expect(fetcher.tunnelled, <bool>[false]);
    expect(harness.subscriptionRepository.items, hasLength(1));
  });

  testWidgets('a whitespace-padded URL is still the URL that is fetched',
      (tester) async {
    await pumpScreen(tester);

    await submit(tester, '  $panelUrl  ');

    expect(harness.subscriptionFetcher.requests, <Uri>[Uri.parse(panelUrl)]);
    // And the row keeps the clean URL: every later refresh reads it back,
    // and a stored `  https://…` would fail forever with no way to edit it.
    expect(stored().url, Uri.parse(panelUrl));
  });

  testWidgets('anything that is not an http URL is refused before the request',
      (tester) async {
    await pumpScreen(tester);

    const refused = <String>[
      // Add tapped on an empty sheet.
      '',
      // Typed without a scheme, which is how people write a URL by hand.
      'panel.example.net/sub/token',
      // A proxy link pasted into the wrong field of the wrong sheet.
      'vless://$uuid@nl-03.example.net:443',
      // A scheme with nothing behind it.
      'https://',
      // A scheme no HTTP client would take.
      'file:///etc/passwd',
    ];

    for (final typed in refused) {
      await tester.enterText(fieldWithLabel(t.import.subscription.url), typed);
      await tester.tap(addButton());
      await tester.pumpAndSettle();

      expect(
        find.text(t.import.subscription.invalidUrl),
        findsOneWidget,
        reason: typed,
      );
    }

    // The point of validating here rather than at the fetcher: nothing was
    // sent anywhere, and nothing was written.
    expect(harness.subscriptionFetcher.callCount, 0);
    expect(harness.subscriptionRepository.items, isEmpty);
    expect(harness.nodeRepository.nodes, isEmpty);
  });

  testWidgets('a self-hosted panel on plain http is accepted', (tester) async {
    await pumpScreen(tester);

    await submit(tester, 'http://192.168.1.10:8080/sub');

    expect(
      harness.subscriptionFetcher.requests,
      <Uri>[Uri.parse('http://192.168.1.10:8080/sub')],
    );
    expect(harness.subscriptionRepository.items, hasLength(1));
  });

  testWidgets('the refusal clears as soon as the URL is edited',
      (tester) async {
    await pumpScreen(tester);

    await submit(tester, 'panel.example.net');
    expect(find.text(t.import.subscription.invalidUrl), findsOneWidget);

    await tester.enterText(fieldWithLabel(t.import.subscription.url), panelUrl);
    await tester.pumpAndSettle();

    // An error line that outlived the typo would accuse a URL that is fine.
    expect(find.text(t.import.subscription.invalidUrl), findsNothing);

    await tester.tap(addButton());
    await tester.pumpAndSettle();
    expect(harness.subscriptionRepository.items, hasLength(1));
  });

  group('the name', () {
    testWidgets('is the typed one, trimmed', (tester) async {
      await pumpScreen(tester);

      await submit(tester, panelUrl, name: '  Home panel  ');

      expect(stored().name, 'Home panel');
    });

    testWidgets('falls back to the host when the field is left empty',
        (tester) async {
      await pumpScreen(tester);

      await submit(tester, panelUrl);

      // Not an empty card on the main screen, and not the token in the path.
      expect(stored().name, 'panel.example.net');
    });
  });

  group('the refresh interval', () {
    testWidgets('offers the four the subscription menu also writes',
        (tester) async {
      await pumpScreen(tester);

      for (final hours in SubscriptionSheet.intervals) {
        expect(
          find.text(t.time.hours(count: hours)),
          findsOneWidget,
          reason: '$hours h',
        );
      }
      final control = tester.widget<SegmentedControl<int>>(
        find.byType(SegmentedControl<int>),
      );
      // A default outside the offered set would draw a control with nothing
      // selected and silently change the value on the first tap.
      expect(
        SubscriptionSheet.intervals,
        contains(Subscription.defaultUpdateIntervalHours),
      );
      expect(control.value, Subscription.defaultUpdateIntervalHours);
    });

    testWidgets('stores the one the user picked', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text(t.time.hours(count: 6)));
      await tester.pumpAndSettle();
      await submit(tester, panelUrl);

      expect(stored().updateIntervalHours, 6);
    });

    testWidgets("the panel's own suggestion wins over the picked one",
        (tester) async {
      // docs/05-ux-flows.md, scenario 3: `profile-update-interval` is the
      // admin telling us how often their server wants to be asked, and the
      // segmented control only fills the gap when no header came.
      final fetcher = _ScriptedFetcher(
        payload: const SubscriptionPayload(body: body, updateIntervalHours: 3),
      );
      await pumpScreen(tester, fetcher: fetcher);

      await tester.tap(find.text(t.time.hours(count: 6)));
      await tester.pumpAndSettle();
      await submit(tester, panelUrl);

      expect(stored().updateIntervalHours, 3);
    });
  });

  testWidgets('auto refresh left off is stored off', (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is CommySwitch &&
            widget.semanticLabel == t.import.subscription.autoUpdate,
      ),
    );
    await tester.pumpAndSettle();
    await submit(tester, panelUrl);

    // The scheduler reads this field; a switch nobody stored would refresh a
    // panel the user asked us to leave alone.
    expect(stored().autoUpdate, isFalse);
  });

  group('when the import fails', () {
    testWidgets('a panel that does not answer is named, and nothing is stored',
        (tester) async {
      await pumpScreen(tester);
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse(panelUrl),
        cause: 'the panel did not answer',
      );

      await submit(tester, panelUrl);

      expect(
        find.text(t.error.subscriptionUnreachable.message),
        findsOneWidget,
      );
      // Retryable, so the way out is a second attempt rather than a dead end.
      expect(find.text(t.common.retry), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
      expect(harness.subscriptionRepository.items, isEmpty);
      expect(harness.nodeRepository.nodes, isEmpty);
    });

    testWidgets('a retry starts from the URL that was already typed',
        (tester) async {
      await pumpScreen(tester);
      harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
        url: Uri.parse(panelUrl),
        cause: 'the panel did not answer',
      );

      await submit(tester, panelUrl);
      expect(
        find.text(t.error.subscriptionUnreachable.message),
        findsOneWidget,
      );

      harness.subscriptionFetcher.failure = null;
      await tester.tap(find.text(t.common.retry));
      await tester.pumpAndSettle();

      // docs/05-ux-flows.md, scenario 1: a failed import keeps the sheet open
      // with the input intact. Retyping a subscription URL by hand is not a
      // recovery path anybody takes.
      expect(find.text(panelUrl), findsOneWidget);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      expect(harness.subscriptionFetcher.callCount, 2);
      expect(harness.subscriptionRepository.items, hasLength(1));
    });

    testWidgets('a page instead of a server list leaves no empty subscription',
        (tester) async {
      // What an expired token actually gets you: the panel's login page with
      // a 200 on it.
      await pumpScreen(
        tester,
        document: '<!doctype html><html><body>Sign in</body></html>',
      );

      await submit(tester, panelUrl);

      expect(find.text(t.error.subscriptionMalformed.message), findsOneWidget);
      expect(harness.subscriptionRepository.items, isEmpty);
      expect(harness.nodeRepository.nodes, isEmpty);
    });
  });

  testWidgets('a sheet dragged away leaves the next one a clean slate',
      (tester) async {
    await pumpEntryPoint(tester);

    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();
    await submit(tester, panelUrl);
    expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);

    // The handle, not `Готово`: the panel's buttons were the only thing that
    // ever cleared the result, and this is the way out that skips them.
    await dragSheetAway(tester);
    expect(find.byType(CommySheetSurface), findsNothing);

    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();

    // Adding a second panel has to start on the form. A sheet that opened on
    // the previous import's report has no URL field on it at all, and nothing
    // here — not the import sheet, not the first-run view — would clear it.
    expect(find.text(t.import.result.imported(count: 2)), findsNothing);
    expect(fieldWithLabel(t.import.subscription.url), findsOneWidget);
    expect(find.text(panelUrl), findsNothing);
  });

  group('a download outliving its sheet', () {
    /// Opens the sheet on a held-open download and submits [panelUrl] into it.
    Future<Completer<void>> startDownload(WidgetTester tester) async {
      final gate = Completer<void>();
      await pumpEntryPoint(
        tester,
        fetcher: _ScriptedFetcher(
          payload: const SubscriptionPayload(body: body),
          gate: gate,
        ),
      );

      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();
      await tester.enterText(
        fieldWithLabel(t.import.subscription.url),
        panelUrl,
      );
      await tester.tap(addButton());
      await tester.pump();

      // Inside the seconds the download takes, which is where the whole
      // question lives.
      expect(tester.widget<CommyButton>(addButton()).isLoading, isTrue);
      return gate;
    }

    testWidgets('reports into the sheet that is still open', (tester) async {
      final gate = await startDownload(tester);

      gate.complete();
      await tester.pumpAndSettle();

      // The other half of the rule: nothing may drop a report the user is
      // sitting in front of waiting for.
      expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);
    });

    testWidgets('is not what the next sheet opens on', (tester) async {
      final gate = await startDownload(tester);

      // The handle, mid-download. The route ends here and takes its reset
      // with it — seconds before the panel answers.
      await dragSheetAway(tester);
      expect(find.byType(CommySheetSurface), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      // Walking away from the sheet does not un-start the import: what the
      // user asked for is stored, and the home screen is where they see it.
      expect(stored().url, Uri.parse(panelUrl));
      expect(harness.nodeRepository.nodes, hasLength(2));

      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();

      // Only the report is dropped. A result written after the route's reset
      // had run would be sitting on the shared controller with nothing left
      // to draw it, and this is the sheet that would come up on it instead of
      // on a URL field.
      expect(find.text(t.import.result.imported(count: 2)), findsNothing);
      expect(fieldWithLabel(t.import.subscription.url), findsOneWidget);
      expect(tester.widget<CommyButton>(addButton()).isLoading, isFalse);
    });
  });

  testWidgets('a second tap while the fetch runs does not import twice',
      (tester) async {
    final gate = Completer<void>();
    final fetcher = _ScriptedFetcher(
      payload: const SubscriptionPayload(body: body),
      gate: gate,
    );
    await pumpScreen(tester, fetcher: fetcher);

    await tester.enterText(fieldWithLabel(t.import.subscription.url), panelUrl);
    await tester.tap(addButton());
    await tester.pump();

    expect(tester.widget<CommyButton>(addButton()).isLoading, isTrue);

    await tester.tap(addButton());
    await tester.pump();
    // Two subscriptions on two ids, pointing at the same panel, is a mess the
    // user has to clean up by hand.
    expect(fetcher.callCount, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(harness.subscriptionRepository.items, hasLength(1));
  });
}

/// A subscription server the test drives by hand.
///
/// The harness's own fake cannot do any of the three things asked of it here:
/// it answers in the same microtask, which leaves no window in which the sheet
/// is busy, it has no way to carry a response header, and it does not record
/// whether the fetch was asked to go through the tunnel.
class _ScriptedFetcher implements SubscriptionFetcher {
  _ScriptedFetcher({required this.payload, this.gate});

  /// What the fetch answers with, headers included.
  final SubscriptionPayload payload;

  /// Held open until the test completes it, when there is one.
  final Completer<void>? gate;

  /// The URLs asked for, in order.
  final List<Uri> requests = <Uri>[];

  /// Whether each of those went through the tunnel, in the same order.
  final List<bool> tunnelled = <bool>[];

  /// How many times a document was asked for.
  int get callCount => requests.length;

  @override
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  }) async {
    requests.add(url);
    tunnelled.add(throughTunnel);
    await gate?.future;
    return Ok<SubscriptionPayload, CommyFailure>(payload);
  }
}
