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

  group('the Auto row', () {
    late CommyTestHarness twoServers;

    setUp(() {
      twoServers = CommyTestHarness(
        nodes: <ProxyNode>[
          testNode(),
          testNode(id: 'node-2', name: 'Warsaw 01', countryCode: 'PL'),
        ],
      );
    });

    tearDown(() => twoServers.dispose());

    Future<List<NodeTile>> pumpTwo(WidgetTester tester) async {
      // Tall enough for the rows under the hero, the Auto row and the
      // toolbar: the list is lazy and builds nothing below the viewport.
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        twoServers.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
      return tester.widgetList<NodeTile>(find.byType(NodeTile)).toList();
    }

    testWidgets('leads the list once there is something to choose between',
        (tester) async {
      final tiles = await pumpTwo(tester);
      final t = Translations();

      expect(tiles.first.name, t.home.auto);
      // Nothing is running, so the row says what the group does instead of
      // naming a server it has not picked.
      expect(tiles.first.descriptors, <String>[t.home.autoSubtitle]);
      expect(tiles.any((tile) => tile.name == 'Amsterdam 03'), isTrue);
    });

    testWidgets('is not offered for a single server', (tester) async {
      await pumpHome(tester, status: const TunnelStatus.idle());
      final t = Translations();

      final tiles = tester.widgetList<NodeTile>(find.byType(NodeTile));
      expect(tiles.length, 1);
      expect(tiles.single.name, isNot(t.home.auto));
    });

    testWidgets('tapping it takes the active mark off the servers',
        (tester) async {
      final t = Translations();
      await pumpTwo(tester);
      // Pick a server first, so there is a mark to take away.
      await tester.tap(find.text('Amsterdam 03'));
      await settle(tester);
      expect(
        tester
            .widgetList<NodeTile>(find.byType(NodeTile))
            .any((tile) => tile.name == 'Amsterdam 03' && tile.isActive),
        isTrue,
      );

      await tester.tap(find.text(t.home.auto));
      await settle(tester);

      final tiles = tester.widgetList<NodeTile>(find.byType(NodeTile)).toList();
      expect(tiles.first.isActive, isTrue);
      expect(tiles.skip(1).any((tile) => tile.isActive), isFalse);
      expect(
        (await twoServers.settingsRepository.read()).valueOrNull!.autoSelect,
        isTrue,
      );
    });
  });

  group('search and order', () {
    late CommyTestHarness three;

    setUp(() {
      three = CommyTestHarness(
        nodes: <ProxyNode>[
          testNode(),
          testNode(
            id: 'node-2',
            name: 'Warsaw 01',
            countryCode: 'PL',
            latency: null,
          ),
          testNode(
            id: 'node-3',
            name: 'Berlin 02',
            countryCode: 'DE',
            latency: const Duration(milliseconds: 12),
          ),
        ],
      );
    });

    tearDown(() => three.dispose());

    /// A phone-wide, very tall surface.
    ///
    /// The list is lazy: rows below the default 600-pixel test viewport are
    /// never built, and with the hero, the Auto row and the toolbar above
    /// them the server rows sit exactly there. Order assertions need every
    /// row on screen at once.
    Future<void> pumpThree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        three.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
    }

    /// Server rows in list order, without the Auto row.
    List<String> serverNames(WidgetTester tester) {
      final auto = Translations().home.auto;
      return <String>[
        for (final tile in tester.widgetList<NodeTile>(find.byType(NodeTile)))
          if (tile.name != auto) tile.name,
      ];
    }

    testWidgets('typing narrows the list to the matching servers',
        (tester) async {
      await pumpThree(tester);

      await tester.enterText(find.byType(SearchField), 'war');
      await settle(tester);

      expect(serverNames(tester), <String>['Warsaw 01']);
    });

    testWidgets('a country code matches whole, not as two letters',
        (tester) async {
      await pumpThree(tester);

      await tester.enterText(find.byType(SearchField), 'de');
      await settle(tester);

      expect(serverNames(tester), <String>['Berlin 02']);
    });

    testWidgets('nothing found says so, and its action clears the search',
        (tester) async {
      await pumpThree(tester);
      final t = Translations();

      await tester.enterText(find.byType(SearchField), 'zzz');
      await settle(tester);
      expect(serverNames(tester), isEmpty);
      expect(find.text(t.home.search.nothing), findsOneWidget);

      await tester.tap(find.text(t.home.search.clear));
      await settle(tester);

      expect(serverNames(tester).length, 3);
      expect(find.text(t.home.search.nothing), findsNothing);
    });

    testWidgets(
        'ordering by latency puts the fastest first and the unmeasured last',
        (tester) async {
      await pumpThree(tester);
      final t = Translations();
      expect(
        serverNames(tester),
        <String>['Amsterdam 03', 'Warsaw 01', 'Berlin 02'],
      );

      await tester.tap(find.byType(CommyChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.home.sort.latency));
      await tester.pumpAndSettle();

      expect(
        serverNames(tester),
        <String>['Berlin 02', 'Amsterdam 03', 'Warsaw 01'],
      );
      // The choice is a setting, so it survives a restart.
      expect(
        (await three.settingsRepository.read()).valueOrNull!.nodeSort,
        NodeSort.latency,
      );
    });

    testWidgets('one server gets neither a search field nor an order chip',
        (tester) async {
      await pumpHome(tester, status: const TunnelStatus.idle());

      expect(find.byType(SearchField), findsNothing);
      expect(find.byType(CommyChip), findsNothing);
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
