import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/screens/import/import_sheet.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #16: the two sheets everything gets into the app through.
///
/// Commy ships with nothing in it — no bundled configs, no catalogue of
/// anybody else's servers — so paste, subscription, QR and file are the whole
/// surface. What is protected here is what the product leans on:
///
/// * all four ways in are offered, and the clipboard is offered only when it
///   actually holds something the parser can read;
/// * the clipboard preview is redacted — the UUID or password sitting in the
///   buffer must never be rendered where a shoulder can read it;
/// * a pasted link ends up in the node repository, not merely on screen, and
///   the same server under two names stays one row there;
/// * an import that fails names the cause and leaves a route to the logs
///   instead of closing on the user and losing what they typed, and closing
///   the result hands the sheet back ready for the next attempt;
/// * the result belongs to the sheet that produced it — one panel at a time,
///   and none of it survives the sheet being dismissed by a gesture.
void main() {
  final t = Translations();

  const uuid = '11111111-2222-3333-4444-555555555555';
  const publicKey = 'aGVsbG8td29ybGQtcHVibGljLWtleQ';
  const amsterdam = 'vless://$uuid@nl-03.example.net:443'
      '?security=reality&type=tcp&pbk=$publicKey&sid=ab12cd34#Amsterdam%2003';
  const warsaw = 'vless://99999999-8888-7777-6666-555555555555'
      '@pl-10.example.net:443'
      '?security=reality&type=tcp&pbk=$publicKey&sid=ef56ab78#Warsaw%2010';
  const junk = 'a shopping list, copied by accident';

  // What the card has to render for `amsterdam`: scheme, host, port and the
  // display name survive, the credential and the whole query do not, and the
  // name reads the way the user named the node — `Amsterdam 03`, not
  // `Amsterdam%2003`, which is the whole point of keeping the fragment.
  // Spelled out rather than re-derived from `Redact.link`, so a regression
  // inside the redactor shows up here as a failure instead of as a matching
  // pair of wrong values.
  const redactedAmsterdam = 'vless://[redacted]@nl-03.example.net:443'
      '?[redacted]#Amsterdam 03';

  // A line the parser has to refuse, carrying a credential: what the panel
  // shows for it is the test of `ImportFailure.redactedLine`.
  const secret = 'SuperSecretPassword';
  const brokenLine = 'ftp://$secret@files.example.net';
  const redactedBrokenLine = 'ftp://[redacted]@files.example.net';

  // The same server a panel has renamed. Identity is protocol, address, port
  // and credential — never the display name — so this is the same row.
  const amsterdamRenamed = 'vless://$uuid@nl-03.example.net:443'
      '?security=reality&type=tcp&pbk=$publicKey&sid=ab12cd34#NL%20premium';

  /// The control that stands in for an entry point other than the `+` button.
  const openLabel = 'open the sheet';

  late CommyTestHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget screen, {
    String? clipboard,
    Completer<void>? gate,
  }) async {
    // Taller than the 800x600 default: four tiles, a heading and a clipboard
    // card do not fit, and a surface that clipped them would be testing the
    // window rather than the sheet.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(clipboard: clipboard);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(body: SingleChildScrollView(child: screen)),
        extra: <Override>[
          if (gate != null)
            importLinksUseCaseProvider.overrideWithValue(
              _GatedLinkImport(
                gate: gate,
                inner: ImportLinksUseCase(
                  parser: CommyLinkParser(),
                  nodes: harness.nodeRepository,
                ),
              ),
            ),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Stands a sheet up behind a button on a route, the way the app opens it.
  ///
  /// `HomeScreen._openImport` clears the import state before it shows the
  /// sheet; the deep link handler and the first-run view show the same sheets
  /// without clearing anything, and this is what they look like.
  Future<void> pumpEntryPoint(
    WidgetTester tester,
    Future<void> Function(BuildContext context) open,
  ) async {
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(open(context)),
              child: const Text(openLabel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the paste modal from the chooser and imports [input] through it.
  Future<void> importThroughPasteModal(
    WidgetTester tester,
    String input,
  ) async {
    await tester.tap(find.text(t.import.paste.title));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CommyTextField), input);
    await tester.tap(find.text(t.import.paste.action));
    await tester.pumpAndSettle();
  }

  /// Every string the renderer was actually handed, fields included.
  ///
  /// `RichText` on its own would miss a text field: `EditableText` does not
  /// lay its content out through one, and a credential parked in a field is
  /// on screen exactly like a credential parked in a label.
  Iterable<String> rendered(WidgetTester tester) => <String>[
        for (final widget in tester.widgetList<RichText>(find.byType(RichText)))
          widget.text.toPlainText(),
        for (final widget
            in tester.widgetList<EditableText>(find.byType(EditableText)))
          widget.controller.text,
      ];

  /// Fails when [secret] reached the screen in any form.
  void expectNotRendered(WidgetTester tester, String secret) {
    expect(
      rendered(tester).where((line) => line.contains(secret)),
      isEmpty,
      reason: 'a credential was rendered: $secret',
    );
  }

  List<ProxyNode> stored() => harness.nodeRepository.nodes;

  group('the import sheet', () {
    testWidgets('offers all four ways in', (tester) async {
      await pumpScreen(tester, const ImportSheet());

      expect(find.text(t.import.title), findsOneWidget);
      expect(find.text(t.import.subscription.title), findsOneWidget);
      expect(find.text(t.import.paste.title), findsOneWidget);
      expect(find.text(t.import.qr.title), findsOneWidget);
      expect(find.text(t.import.file.title), findsOneWidget);
      // Nothing in the clipboard, so no card offering to paste it: an offer
      // that leads nowhere costs the user the one tap they were promised.
      expect(find.text(t.import.clipboard.paste), findsNothing);
    });

    testWidgets('stays quiet when the clipboard holds nothing importable',
        (tester) async {
      await pumpScreen(tester, const ImportSheet(), clipboard: junk);

      // Offering to paste a shopping list is worse than offering nothing: the
      // button would fail on the one input the user is told will work.
      expect(find.text(t.import.clipboard.paste), findsNothing);
      expect(find.text(t.import.paste.title), findsOneWidget);
    });

    testWidgets('offers the clipboard when it holds a link, and counts it',
        (tester) async {
      await pumpScreen(tester, const ImportSheet(), clipboard: amsterdam);

      expect(
        find.text(
          t.import.clipboard.found(
            count: t.import.clipboard.one(protocol: Protocol.vless.wireName),
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(t.import.clipboard.paste), findsOneWidget);
    });

    testWidgets('counts a whole list, not just the first line', (tester) async {
      await pumpScreen(
        tester,
        const ImportSheet(),
        clipboard: '$amsterdam\n$warsaw',
      );

      expect(
        find.text(
          t.import.clipboard.found(count: t.import.clipboard.many(count: 2)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows the clipboard redacted, never the credential',
        (tester) async {
      await pumpScreen(tester, const ImportSheet(), clipboard: amsterdam);

      // The name survives because that is what makes the preview readable;
      // the UUID and the Reality key do not survive at all.
      expect(find.text(redactedAmsterdam), findsOneWidget);
      expectNotRendered(tester, uuid);
      expectNotRendered(tester, publicKey);
    });

    testWidgets('pasting from the clipboard stores the server', (tester) async {
      await pumpScreen(tester, const ImportSheet(), clipboard: amsterdam);

      await tester.tap(find.text(t.import.clipboard.paste));
      await tester.pumpAndSettle();

      final node = stored().single;
      expect(node.protocol, Protocol.vless);
      expect(node.host, 'nl-03.example.net');
      expect(node.port, 443);
      expect(node.name, 'Amsterdam 03');
      // What is imported is the clipboard, not the redacted line the card
      // draws: a node stored from the preview would carry no credential and
      // fail on the first connect instead of here.
      expect(node.params['uuid'], uuid);
      expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);
      // A result the user cannot dismiss is a dead end, and the chooser is
      // gone by now.
      expect(find.text(t.common.done), findsOneWidget);
      expect(find.text(t.import.subscription.title), findsNothing);
    });

    testWidgets('pasting a list stores every server in it', (tester) async {
      await pumpScreen(
        tester,
        const ImportSheet(),
        clipboard: '$amsterdam\n$warsaw',
      );

      await tester.tap(find.text(t.import.clipboard.paste));
      await tester.pumpAndSettle();

      expect(
        stored().map((node) => node.host),
        <String>['nl-03.example.net', 'pl-10.example.net'],
      );
      expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);
    });

    testWidgets('a store that refuses says so instead of claiming success',
        (tester) async {
      await pumpScreen(tester, const ImportSheet(), clipboard: amsterdam);
      harness.nodeRepository.failure = const StorageFailure('disk is full');

      await tester.tap(find.text(t.import.clipboard.paste));
      await tester.pumpAndSettle();

      expect(stored(), isEmpty);
      expect(find.text(t.error.title), findsOneWidget);
      expect(find.text(t.error.storage.message), findsOneWidget);
      // Cause, action, and a route to the logs: an error without one is half
      // an error (docs/05-ux-flows.md). The action is the one the failure
      // itself names, not a generic dismissal.
      expect(find.text(t.error.storage.action), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
      // And the choices are gone, so the result cannot be mistaken for the
      // sheet still waiting on a tap.
      expect(find.text(t.import.subscription.title), findsNothing);
    });

    testWidgets('the paste tile opens a field to paste into', (tester) async {
      await pumpScreen(tester, const ImportSheet());

      await tester.tap(find.text(t.import.paste.title));
      await tester.pumpAndSettle();

      expect(find.byType(CommyTextField), findsOneWidget);
      expect(find.text(t.import.paste.label), findsOneWidget);
    });

    testWidgets('closing a result hands the sheet back, not the result',
        (tester) async {
      await pumpScreen(tester, const ImportSheet());
      await importThroughPasteModal(tester, amsterdam);

      // One `Done` on screen, not two: the modal owns the result it produced,
      // and the chooser underneath still has its four tiles. This test used to
      // need `.last` here to reach past a second copy of the panel.
      expect(find.text(t.common.done), findsOneWidget);
      await tester.tap(find.text(t.common.done));
      await tester.pumpAndSettle();

      // Closing is what clears the result. Leave it behind and the next tap
      // on `+` opens on the last import's outcome instead of on the choices,
      // with no way back to them.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.byType(CommyTextField), findsNothing);
      expect(find.text(t.import.subscription.title), findsOneWidget);
      expect(find.text(t.import.paste.title), findsOneWidget);
    });
  });

  /// Who owns the result, given that all four paths share one controller.
  ///
  /// The buttons on the result panel are the only thing that clears it, and
  /// the `+` on the home screen the only entry point that clears it before
  /// opening. The scrim, the drag handle and the back gesture go around both,
  /// and so do the deep link and the first-run view.
  group('the result belongs to the sheet that produced it', () {
    testWidgets('the chooser keeps its four tiles while the modal reports',
        (tester) async {
      await pumpScreen(tester, const ImportSheet());
      await importThroughPasteModal(tester, junk);

      // One panel, on the sheet the user is looking at. A second copy of it
      // under the scrim is what they land on the moment the modal is dragged
      // away instead of closed.
      expect(find.byType(ImportResultPanel), findsOneWidget);
      expect(find.text(t.import.subscription.title), findsOneWidget);
      expect(find.text(t.import.file.title), findsOneWidget);
    });

    testWidgets('a modal dragged away hands the chooser back, not a result',
        (tester) async {
      await pumpScreen(tester, const ImportSheet());
      await importThroughPasteModal(tester, junk);

      await tester.drag(find.byType(CommySheetSurface), const Offset(0, 600));
      await tester.pumpAndSettle();

      // Dragging a sheet away is not a way of accepting what it was showing.
      // What is underneath has to be the four ways in.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.text(t.error.title), findsNothing);
      expect(find.text(t.import.paste.title), findsOneWidget);
      expect(find.text(t.import.file.title), findsOneWidget);
    });

    testWidgets('a sheet dismissed by the scrim leaves the next one clean',
        (tester) async {
      await pumpEntryPoint(tester, PasteSheet.show);

      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), junk);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();
      expect(find.text(t.error.title), findsOneWidget);

      // The scrim, not the button: it is the way out that never went through
      // `reset`, and it is how a deep link's sheet is usually left.
      await tester.tapAt(
        Offset(
          tester.getCenter(find.byType(CommySheetSurface)).dx,
          tester.getTopLeft(find.byType(CommySheetSurface)).dy / 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommySheetSurface), findsNothing);

      await tester.tap(find.text(openLabel));
      await tester.pumpAndSettle();

      // Only the `+` on the home screen clears the state before opening. A
      // deep link and the first-run view do not, and a sheet that opened on
      // the last import's error has no field to type into at all.
      expect(find.text(t.error.title), findsNothing);
      expect(find.byType(CommyTextField), findsOneWidget);
    });

    testWidgets('an import still running reports into the modal it is in',
        (tester) async {
      final gate = Completer<void>();
      await pumpScreen(tester, const ImportSheet(), gate: gate);

      await tester.tap(find.text(t.import.paste.title));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), amsterdam);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      // Nothing may drop the report of an import whose sheet the user is
      // still sitting in front of, however long it took to land.
      expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);
    });

    testWidgets('an import landing after its modal is gone reports to nobody',
        (tester) async {
      final gate = Completer<void>();
      await pumpScreen(tester, const ImportSheet(), gate: gate);

      await tester.tap(find.text(t.import.paste.title));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), amsterdam);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pump();

      // Dragged away mid-import: the route's end clears the controller, and
      // the import is still seconds from having anything to say.
      await tester.drag(find.byType(CommySheetSurface), const Offset(0, 600));
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();

      // The server landed — the user asked for it and walking away from the
      // sheet does not un-ask — but the chooser underneath is not the place
      // that report was going, and it keeps its four tiles.
      expect(stored().single.host, 'nl-03.example.net');
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.text(t.import.result.imported(count: 1)), findsNothing);
      expect(find.text(t.import.paste.title), findsOneWidget);
      expect(find.text(t.import.file.title), findsOneWidget);
    });

    testWidgets(
        'an import that outlived its modal is not what the next one opens on',
        (tester) async {
      final gate = Completer<void>();
      await pumpScreen(tester, const ImportSheet(), gate: gate);

      await tester.tap(find.text(t.import.paste.title));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), amsterdam);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pump();
      await tester.drag(find.byType(CommySheetSurface), const Offset(0, 600));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.import.paste.title));
      await tester.pumpAndSettle();

      // The next sheet is the one the abandoned result would have surfaced
      // in, and a modal opened on it has no field to paste the next list into.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.byType(CommyTextField), findsOneWidget);
    });
  });

  group('the paste sheet', () {
    testWidgets('imports what was typed and says how much landed',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(find.byType(CommyTextField), amsterdam);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      final node = stored().single;
      expect(node.host, 'nl-03.example.net');
      expect(node.params['uuid'], uuid);
      expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);
    });

    testWidgets('a link tapped elsewhere arrives filled in, not imported',
        (tester) async {
      // The deep link opens the sheet; the user still sees what arrived and
      // still presses the button. Importing on arrival would let any app on
      // the device add a server behind their back.
      await pumpScreen(tester, const PasteSheet(initialText: amsterdam));

      expect(find.text(amsterdam), findsOneWidget);
      expect(stored(), isEmpty);

      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      expect(stored().single.host, 'nl-03.example.net');
    });

    testWidgets('junk names the cause and keeps a route to the logs',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(find.byType(CommyTextField), junk);
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      expect(stored(), isEmpty);
      expect(find.text(t.error.title), findsOneWidget);
      expect(find.text(t.error.subscriptionMalformed.message), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
    });

    testWidgets('an empty field imports nothing and leaves the sheet alone',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), '   \n  ');
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      // No result panel, no failure banner: nothing was asked for, so nothing
      // is reported.
      expect(stored(), isEmpty);
      expect(find.byType(CommyTextField), findsOneWidget);
      expect(find.text(t.error.title), findsNothing);
      expect(find.text(t.import.result.nothing), findsNothing);
    });

    testWidgets('one broken line does not sink the rest of the list',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(
        find.byType(CommyTextField),
        '$amsterdam\n$brokenLine\n$warsaw',
      );
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      expect(
        stored().map((node) => node.host),
        <String>['nl-03.example.net', 'pl-10.example.net'],
      );
      expect(find.text(t.import.result.imported(count: 2)), findsOneWidget);
      expect(find.text(t.import.result.skipped(count: 1)), findsOneWidget);
    });

    testWidgets('the same server under two names stays one row',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(
        find.byType(CommyTextField),
        '$amsterdam\n$amsterdamRenamed',
      );
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      // A panel renames its servers constantly. Identity is the endpoint and
      // the credential, never the label, so a renamed list must not grow a
      // second row: the measured latency and the user's grouping hang off
      // that id. The later name wins, because it is the newer one.
      final node = stored().single;
      expect(node.host, 'nl-03.example.net');
      expect(node.name, 'NL premium');
    });

    testWidgets('the skipped lines are shown redacted', (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(
        find.byType(CommyTextField),
        '$amsterdam\n$brokenLine',
      );
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.import.result.showSkipped));
      await tester.pumpAndSettle();

      // A line that failed to parse still carries a password.
      expect(find.text(redactedBrokenLine), findsOneWidget);
      expectNotRendered(tester, secret);
    });

    testWidgets('a comment line is skipped without being called an error',
        (tester) async {
      await pumpScreen(tester, const PasteSheet());

      await tester.enterText(
        find.byType(CommyTextField),
        '# my panel, exported 2026-08-04\n$amsterdam',
      );
      await tester.tap(find.text(t.import.paste.action));
      await tester.pumpAndSettle();

      expect(stored(), hasLength(1));
      expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);
      expect(find.text(t.import.result.skipped(count: 1)), findsNothing);
    });
  });
}

/// An import the test holds open, so it can be inside the gap.
///
/// The clipboard and paste paths answer in the same microtask, which leaves no
/// window in which a sheet can be dismissed while its import is in flight —
/// and that window is the only place the bug lives. Everything but the timing
/// is the shipping use case.
class _GatedLinkImport implements ImportLinksUseCase {
  _GatedLinkImport({required this.inner, required this.gate});

  /// The real import, run once [gate] is completed.
  final ImportLinksUseCase inner;

  /// Held until the test lets the import finish.
  final Completer<void> gate;

  @override
  LinkParser get parser => inner.parser;

  @override
  NodeRepository get nodes => inner.nodes;

  @override
  Future<Result<ParseOutcome, CommyFailure>> call(
    String input, {
    String? groupId,
  }) async {
    await gate.future;
    return inner(input, groupId: groupId);
  }
}
