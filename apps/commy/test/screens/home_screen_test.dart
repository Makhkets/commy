import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The home screen in every state it can be in.
///
/// The six tunnel states are the contract from docs/05-ux-flows.md: each one
/// has to be distinguishable, and the two that are not "up" have to hide the
/// check button rather than disable it.
void main() {
  late CommyTestHarness harness;

  setUp(() {
    harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
  });

  tearDown(() => harness.dispose());

  Future<void> pumpHome(WidgetTester tester, {TunnelStatus? status}) async {
    await tester.pumpWidget(
      harness.wrap(const HomeScreen(), status: status),
    );
    await settle(tester);
  }

  ConnectState stateOf(WidgetTester tester) {
    return tester.widget<ConnectButton>(find.byType(ConnectButton)).state;
  }

  group('tunnel states', () {
    testWidgets('idle draws the idle button and no check button',
        (tester) async {
      await pumpHome(tester, status: const TunnelStatus.idle());

      expect(stateOf(tester), ConnectState.idle);
      expect(find.byType(CheckButton), findsNothing);
    });

    testWidgets('starting draws the starting button', (tester) async {
      await pumpHome(tester, status: const TunnelStatus.starting());

      expect(stateOf(tester), ConnectState.starting);
      expect(find.byType(CheckButton), findsNothing);
    });

    testWidgets('connected draws the check button', (tester) async {
      await pumpHome(
        tester,
        status: TunnelStatus.connected(since: CommyTestHarness.now),
      );

      expect(stateOf(tester), ConnectState.connected);
      expect(find.byType(CheckButton), findsOneWidget);
    });

    testWidgets('checking keeps the check button and spins it', (tester) async {
      await pumpHome(
        tester,
        status: TunnelStatus.checking(since: CommyTestHarness.now),
      );

      expect(stateOf(tester), ConnectState.checking);
      final button = tester.widget<CheckButton>(find.byType(CheckButton));
      expect(button.isChecking, isTrue);
    });

    testWidgets('stopping draws the stopping button', (tester) async {
      await pumpHome(tester, status: const TunnelStatus.stopping());

      expect(stateOf(tester), ConnectState.stopping);
      expect(find.byType(CheckButton), findsNothing);
    });

    testWidgets('error shows a cause, an action and a route to the logs',
        (tester) async {
      await pumpHome(
        tester,
        status: const TunnelStatus.error(CommyFailure.permissionDenied()),
      );
      final t = Translations();

      expect(stateOf(tester), ConnectState.error);
      // Cause.
      expect(find.text(t.error.permissionDenied.message), findsOneWidget);
      // Action.
      expect(find.text(t.error.permissionDenied.action), findsOneWidget);
      // And the way to diagnostics, because this action does not go there.
      expect(find.text(t.error.openLogs), findsOneWidget);
    });
  });

  group('mandatory screen states', () {
    testWidgets('shows a skeleton before the first read lands', (tester) async {
      await tester.pumpWidget(
        harness.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      // No settle: this is the frame before the repository stream fires.
      expect(find.byType(CommySkeleton), findsWidgets);
    });

    testWidgets('empty offers four ways in and explains the emptiness',
        (tester) async {
      final empty = CommyTestHarness();
      addTearDown(empty.dispose);

      await tester.pumpWidget(
        empty.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
      final t = Translations();

      expect(find.text(t.home.empty.title), findsOneWidget);
      expect(find.text(t.home.empty.body), findsOneWidget);
      expect(find.text(t.home.empty.subscription), findsOneWidget);
      expect(find.text(t.home.empty.scan), findsOneWidget);
      expect(find.text(t.home.empty.file), findsOneWidget);
      expect(find.text(t.home.empty.paste), findsOneWidget);
      // Nothing to connect to means no connect button at all.
      expect(find.byType(ConnectButton), findsNothing);
    });

    testWidgets('a clipboard link is offered before it is pasted',
        (tester) async {
      final withClipboard = CommyTestHarness(
        clipboard: 'vless://11111111-2222-3333-4444-555555555555'
            '@nl-03.example.net:443?security=reality&pbk=abc&sid=ab12cd34'
            '#Amsterdam%2003',
      );
      addTearDown(withClipboard.dispose);

      await tester.pumpWidget(
        withClipboard.wrap(
          const HomeScreen(),
          status: const TunnelStatus.idle(),
        ),
      );
      await settle(tester);
      final t = Translations();

      expect(find.text(t.home.empty.clipboardFound), findsOneWidget);
      expect(find.text(t.home.empty.pasteAndConnect), findsOneWidget);
    });

    testWidgets('content lists the stored server with its descriptors',
        (tester) async {
      await pumpHome(tester, status: const TunnelStatus.idle());

      expect(find.byType(NodeTile), findsOneWidget);
      final tile = tester.widget<NodeTile>(find.byType(NodeTile));
      expect(tile.name, 'Amsterdam 03');
      expect(tile.descriptors, <String>['VLESS', 'Reality', 'TCP']);
      expect(tile.countryCode, 'NL');
    });
  });

  testWidgets('a redacted clipboard preview never shows the credential',
      (tester) async {
    const uuid = '11111111-2222-3333-4444-555555555555';
    final withClipboard = CommyTestHarness(
      clipboard: 'vless://$uuid@nl-03.example.net:443'
          '?security=reality&pbk=abc&sid=ab12cd34#Amsterdam%2003',
    );
    addTearDown(withClipboard.dispose);

    await tester.pumpWidget(
      withClipboard.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
    );
    await settle(tester);

    final shown = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join('\n');
    expect(shown.contains(uuid), isFalse, reason: 'rule R3');
  });
}
