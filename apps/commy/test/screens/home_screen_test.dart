import 'dart:io';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/home/widgets/auto_row.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// What an import started from the first-run view does with its result.
  ///
  /// The four sheets report through [ImportResultPanel] because each owns a
  /// route. The file tile and the clipboard offer own nothing: they used to
  /// call the shared import controller and render none of it, so a parse that
  /// failed left the screen silent — and the next sheet opened on that stale
  /// failure instead of on its own controls.
  group('imports started from the first-run view', () {
    final t = Translations();

    const link = 'vless://11111111-2222-3333-4444-555555555555'
        '@nl-03.example.net:443?security=reality&type=tcp'
        '&pbk=aGVsbG8td29ybGQtcHVibGljLWtleQ&sid=ab12cd34#Amsterdam%2003';
    const junk = 'a shopping list, copied by accident';

    late CommyTestHarness firstRun;

    /// The home screen with nothing in it, and [clipboard] in the buffer.
    Future<void> pumpFirstRun(WidgetTester tester, {String? clipboard}) async {
      firstRun = CommyTestHarness(clipboard: clipboard);
      addTearDown(firstRun.dispose);
      await tester.pumpWidget(
        firstRun.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
    }

    /// Runs an import out, along with the modal that reports it.
    ///
    /// Two clocks are in play. A file import is started in the real one (see
    /// [tapFileTile]) and so is the route future the sheet clears itself on,
    /// while the modal animates on the fake clock a widget test pumps. So
    /// each round hands the event loop back once and pumps twice, and there
    /// are two rounds: one to get the result reported, one to let the route
    /// that carries it finish opening or closing.
    ///
    /// Not `pumpAndSettle`: the clipboard path ends with the fake core
    /// running, and its stats ticker never lets the tree go quiet.
    Future<void> settleModal(WidgetTester tester) async {
      for (var round = 0; round < 2; round++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
    }

    /// What the shared import controller is holding right now.
    ImportState importState(WidgetTester tester) {
      return ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
        listen: false,
      ).read(importControllerProvider);
    }

    /// Points `FilePicker.pickFile` at [path] for the rest of the test.
    ///
    /// The static delegates to `FilePickerPlatform.instance`, and the method
    /// channel behind the default instance has nothing on the other end here.
    /// `null` stands for a picker the user dismissed.
    void usePicker(String? path) {
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _FakePicker(
        path == null ? null : _PickedFile(Uri.file(path)),
      );
      addTearDown(() => FilePickerPlatform.instance = previous);
    }

    /// A config file on disk, holding [contents] and removed with the test.
    String configFile(String contents) {
      final directory = Directory.systemTemp.createTempSync('commy_first_run');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/servers.txt')
        ..writeAsStringSync(contents);
      return file.path;
    }

    /// Opens the file tile and lets the import behind it report.
    ///
    /// The tap is made outside the fake clock on purpose: the import opens
    /// the picked file with `dart:io`, and a read started under that clock
    /// never comes back however many frames are pumped at it.
    Future<void> tapFileTile(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.text(t.home.empty.file));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settleModal(tester);
    }

    /// Dismisses the modal by the scrim: the way out that goes through none
    /// of the result panel's own buttons.
    Future<void> tapScrim(WidgetTester tester) async {
      await tester.tapAt(
        Offset(
          tester.getCenter(find.byType(CommySheetSurface)).dx,
          tester.getTopLeft(find.byType(CommySheetSurface)).dy / 2,
        ),
      );
      await settleModal(tester);
    }

    testWidgets('a file that does not parse names the cause, not silence',
        (tester) async {
      usePicker(configFile(junk));
      await pumpFirstRun(tester);

      await tapFileTile(tester);

      // Cause, action and the route to the logs — CLAUDE.md §6. This screen
      // used to show none of the three: the failure sat on the shared
      // controller with nothing rendering it.
      expect(find.byType(ImportResultPanel), findsOneWidget);
      expect(find.text(t.error.title), findsOneWidget);
      expect(find.text(t.error.subscriptionMalformed.message), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
    });

    testWidgets(
        'a reported failure does not follow the user into the next '
        'sheet', (tester) async {
      usePicker(configFile(junk));
      await pumpFirstRun(tester);
      await tapFileTile(tester);
      expect(find.text(t.error.title), findsOneWidget);

      await tapScrim(tester);
      await tester.tap(find.text(t.home.empty.subscription));
      await settleModal(tester);

      // The subscription sheet with its own field, not the last import's
      // error sitting on it with no way back to the controls.
      expect(find.text(t.error.title), findsNothing);
      expect(find.text(t.import.subscription.url), findsOneWidget);
    });

    testWidgets(
        'a file that imports says how much landed and hands over the '
        'list', (tester) async {
      usePicker(configFile(link));
      await pumpFirstRun(tester);

      await tapFileTile(tester);
      expect(find.text(t.import.result.imported(count: 1)), findsOneWidget);

      await tester.tap(find.text(t.common.done));
      await settleModal(tester);

      // Closing the report leaves the user on a home screen with the server
      // on it, and nothing on the controller the next sheet would open on.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.byType(NodeTile), findsOneWidget);
      expect(importState(tester), ImportState.idle);
    });

    testWidgets('a dismissed picker reports nothing', (tester) async {
      usePicker(null);
      await pumpFirstRun(tester);

      await tapFileTile(tester);

      // Nothing was asked for, so there is nothing to say: no modal, and the
      // four ways in are still where they were.
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(find.text(t.home.empty.file), findsOneWidget);
      expect(importState(tester), ImportState.idle);
    });

    testWidgets('a clipboard import that fails reports the cause',
        (tester) async {
      await pumpFirstRun(tester, clipboard: link);
      firstRun.nodeRepository.failure = const StorageFailure('disk is full');

      await tester.tap(find.text(t.home.empty.pasteAndConnect));
      await settleModal(tester);

      expect(firstRun.nodeRepository.nodes, isEmpty);
      expect(find.byType(ImportResultPanel), findsOneWidget);
      expect(find.text(t.error.storage.message), findsOneWidget);
      expect(find.text(t.error.storage.action), findsOneWidget);
      expect(find.text(t.error.openLogs), findsOneWidget);
    });

    testWidgets('a clipboard import that works lands on the server list',
        (tester) async {
      await pumpFirstRun(tester, clipboard: link);

      await tester.tap(find.text(t.home.empty.pasteAndConnect));
      await settleModal(tester);

      // The success reports itself: the server list, with the tunnel coming
      // up on it. No modal in the way of the sixty-second path, and nothing
      // left on the controller for the next sheet to open on.
      expect(find.byType(NodeTile), findsOneWidget);
      expect(find.byType(ImportResultPanel), findsNothing);
      expect(firstRun.core.startCalls, 1);
      expect(importState(tester), ImportState.idle);

      // The fake core is running by now; its stats ticker has to be stopped
      // inside the body, because a timer that outlives the tree fails a
      // widget test.
      firstRun.core.reset();
      await tester.pump();
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

  /// The chip under the disc, and the list its chevron opens.
  ///
  /// It used to scroll the screen's own list instead — on the argument that a
  /// modal over those rows would be the same list twice — and on a real
  /// device that read as a chevron that does nothing. It opens a picker now:
  /// the servers of the chosen subscription, one tap from the button.
  group('the selected-server chip', () {
    late CommyTestHarness several;

    setUp(() async {
      several = CommyTestHarness(
        subscriptions: <Subscription>[
          testSubscription(),
          testSubscription(id: 'sub-2', name: 'Second panel'),
        ],
        nodes: <ProxyNode>[
          testNode(subscriptionId: 'sub-1'),
          testNode(id: 'node-2', name: 'Warsaw 01', subscriptionId: 'sub-1'),
          testNode(id: 'node-3', name: 'Berlin 02', subscriptionId: 'sub-2'),
        ],
      );
      await several.settingsRepository.writeSelectedNodeId('node-1');
    });

    tearDown(() => several.dispose());

    Finder inSheet(Finder matching) => find.descendant(
          of: find.byType(CommySheetSurface),
          matching: matching,
        );

    Future<void> openPicker(WidgetTester tester) async {
      await tester.pumpWidget(
        several.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
      await tester.tap(find.byType(SelectedNode));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('opens the servers of the chosen subscription, and only them',
        (tester) async {
      await openPicker(tester);

      expect(find.byType(CommySheetSurface), findsOneWidget);
      expect(inSheet(find.text('My panel')), findsOneWidget);
      expect(inSheet(find.text('Amsterdam 03')), findsOneWidget);
      expect(inSheet(find.text('Warsaw 01')), findsOneWidget);
      expect(
        inSheet(find.text('Berlin 02')),
        findsNothing,
        reason: 'That server belongs to the other panel.',
      );
      // Auto is a choice of server too, and it belongs to no panel.
      expect(inSheet(find.byType(AutoRow)), findsOneWidget);
    });

    testWidgets('a tap picks the server and closes the list', (tester) async {
      await openPicker(tester);

      await tester.tap(inSheet(find.text('Warsaw 01')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(CommySheetSurface), findsNothing);
      final stored = await several.settingsRepository.readSelectedNodeId();
      expect(stored.valueOrNull, 'node-2');
      expect(
        tester.widget<SelectedNode>(find.byType(SelectedNode)).name,
        'Warsaw 01',
      );
    });

    testWidgets('ignores the search typed over the list underneath',
        (tester) async {
      await tester.pumpWidget(
        several.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'berlin');
      await settle(tester);

      await tester.tap(find.byType(SelectedNode));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(inSheet(find.text('Amsterdam 03')), findsOneWidget);
      expect(inSheet(find.text('Warsaw 01')), findsOneWidget);
    });

    testWidgets('draws no chevron over a single server', (tester) async {
      final one = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
      addTearDown(one.dispose);
      await tester.pumpWidget(
        one.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);

      expect(
        tester.widget<SelectedNode>(find.byType(SelectedNode)).onTap,
        isNull,
        reason: 'One server is not a choice; a chevron would promise one.',
      );
    });
  });

  /// A panel types the country into the name as a flag emoji, and that is the
  /// only place it exists. On a device the list drew a globe in the flag slot
  /// and the emoji beside it; the flag belongs in the slot.
  group('a flag typed into the name', () {
    late CommyTestHarness flagged;

    setUp(() async {
      flagged = CommyTestHarness(
        nodes: <ProxyNode>[
          testNode(name: '🇨🇿 AXM VPN - Czech', countryCode: null),
          testNode(
            id: 'node-2',
            name: '🇮🇹 AXM VPN - Italy',
            countryCode: null,
          ),
        ],
      );
      await flagged.settingsRepository.writeSelectedNodeId('node-1');
    });

    tearDown(() => flagged.dispose());

    /// Tall enough that the rows under the hero are really built: a lazy list
    /// does not lay out what is below the fold, and these tests read the rows.
    void useTallWindow(WidgetTester tester) {
      tester.view
        ..physicalSize = const Size(420, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('is drawn in the flag slot of the row, not in its text',
        (tester) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        flagged.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);

      final tiles = tester.widgetList<NodeTile>(find.byType(NodeTile)).toList();
      final czech = tiles.firstWhere((tile) => tile.countryCode == 'CZ');
      expect(czech.name, 'AXM VPN - Czech');
      final italy = tiles.firstWhere((tile) => tile.countryCode == 'IT');
      expect(italy.name, 'AXM VPN - Italy');
    });

    testWidgets('is drawn in the chip under the button as well',
        (tester) async {
      await tester.pumpWidget(
        flagged.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);

      final chip = tester.widget<SelectedNode>(find.byType(SelectedNode));
      expect(chip.name, 'AXM VPN - Czech');
      expect((chip.flag! as CountryFlag).countryCode, 'CZ');
    });

    testWidgets('is found by typing the country it names', (tester) async {
      useTallWindow(tester);
      await tester.pumpWidget(
        flagged.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
      );
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'it');
      await settle(tester);

      // Scoped to the rows: the chip under the button goes on naming the
      // chosen server whatever the search says.
      Finder row(String name) => find.descendant(
            of: find.byType(NodeTile),
            matching: find.text(name),
          );
      expect(row('AXM VPN - Italy'), findsOneWidget);
      expect(row('AXM VPN - Czech'), findsNothing);
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

/// A file picker that answers with a fixed file instead of the platform's.
///
/// `FilePicker.pickFile` is a static that delegates to
/// `FilePickerPlatform.instance`, which is the only seam: the method channel
/// behind the default instance has nothing on the other end in a widget test.
final class _FakePicker extends FilePickerPlatform {
  _FakePicker(this.file);

  /// What the picker comes back with. `null` is a picker the user dismissed.
  final PlatformFile? file;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    // Spelled out where the interface leaves it implicit: `strict-inference`
    // will not take a function type with an inferred return.
    dynamic Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    return file;
  }
}

/// The one thing the import reads off a picked file: where it is on disk.
///
/// `ImportController.importFile` takes the path and opens the file itself, so
/// the members below would need `XFile` — a type `file_picker` does not
/// re-export — and nothing in this flow reaches them.
final class _PickedFile extends PlatformFile {
  _PickedFile(this.uri);

  @override
  final Uri uri;

  @override
  String get name => uri.pathSegments.last;

  @override
  Never get xFile => throw UnimplementedError();

  @override
  Never lengthSync() => throw UnimplementedError();

  @override
  Never length() => throw UnimplementedError();

  @override
  Never readAsBytes() => throw UnimplementedError();

  @override
  Never readAsByteStream() => throw UnimplementedError();
}
