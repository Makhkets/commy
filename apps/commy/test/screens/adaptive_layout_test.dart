import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_router.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/router/app_sections.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/home/widgets/hero_area.dart';
import 'package:commy/src/screens/settings/appearance_screen.dart';
import 'package:commy/src/screens/settings/dns_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/widgets/failure_view.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/commy_test_app.dart';

/// Queue item #19. Above 600 dp the app was a stretched phone.
///
/// `AdaptiveScaffold` has shipped all three layouts from the start, but a
/// screen that hands it `destinations: []` gets neither rail nor sidebar —
/// the shell has nothing to draw. Every screen did exactly that, so the two
/// wide layouts differed from the phone only in how much empty space they
/// had. docs/05-ux-flows.md calls that a mistake in as many words.
///
/// These tests pin the fix from both ends. Below the first breakpoint nothing
/// may appear — no rail, and the cog and the back arrow stay the only way
/// between sections, because the phone was never broken and growing it a
/// navigation bar would be the regression `MobileShell` warns about. From
/// 600 dp up the rail has to be there with the right entry lit, including on
/// screens nested two levels down: someone editing DNS is inside Routing, and
/// the navigation has to say so.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  /// Pumps [screen] into a window [width] logical pixels wide.
  ///
  /// The height is generous by default on purpose. These tests are about the
  /// width, and a screen clipped by the 600 dp default height would fail for
  /// the other reason — the one test that cares about a short window asks for
  /// one explicitly.
  Future<void> pumpAt(
    WidgetTester tester,
    Widget screen, {
    required double width,
    double height = 1600,
    List<ProxyNode>? nodes,
    TunnelStatus? status,
    bool settled = true,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(nodes: nodes ?? <ProxyNode>[testNode()]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(harness.wrap(screen, status: status));
    if (settled) {
      await settle(tester);
    }
  }

  /// The rail's own buttons, and nothing else.
  ///
  /// The app bar lives inside the same shell and is built from the same
  /// button — on the home screen its cog even carries the same accessible
  /// name as the Settings destination — so a finder by type or by label would
  /// catch both. The navigation icon size separates them: the rail asks for
  /// [CommySizes.iconNav], every other button takes the default control size.
  Finder railButtons() => find.byWidgetPredicate(
        (widget) =>
            widget is CommyIconButton && widget.size == CommySizes.iconNav,
      );

  /// The accessible name of the one rail button drawn as selected.
  String selectedRailLabel(WidgetTester tester) {
    final lit = <CommyIconButton>[
      for (final button in tester.widgetList<CommyIconButton>(railButtons()))
        if (button.isSelected) button,
    ];
    expect(
      lit,
      hasLength(1),
      reason: 'The rail marks exactly one section as the one you are in.',
    );
    return lit.single.semanticLabel;
  }

  /// The one rail button that names [section].
  Finder railButtonFor(AppSection section) => find.byWidgetPredicate(
        (widget) =>
            widget is CommyIconButton &&
            widget.size == CommySizes.iconNav &&
            widget.semanticLabel == section.label(t),
      );

  late GoRouter router;

  /// Pumps the app's own router at [width], so a rail tap really navigates.
  ///
  /// Everything above pumps one screen under a plain `MaterialApp`, which is
  /// enough to ask what the shell was handed and not enough to ask where a
  /// tap goes: [AppSection.select] calls `context.go`, and with no router
  /// above it there is nowhere to go. Here the routes, the screens and the
  /// sections are all the shipping ones; only the repositories are fakes.
  Future<void> pumpRouterAt(
    WidgetTester tester, {
    required double width,
  }) async {
    tester.view
      ..physicalSize = Size(width, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides(status: const TunnelStatus.idle()),
        child: TranslationProvider(
          child: Builder(
            builder: (context) {
              router = ProviderScope.containerOf(
                context,
                listen: false,
              ).read(routerProvider);
              return MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: CommyTheme.dark,
                locale: TranslationProvider.of(context).flutterLocale,
                supportedLocales: AppLocaleUtils.supportedLocales,
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                routerConfig: router,
              );
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Taps a rail entry and lets the route it goes to finish arriving.
  ///
  /// Not `pumpAndSettle`: the clock provider is pinned but the fake core's
  /// tick is not, and a settle that waits for the tree to go quiet never
  /// returns. A page transition is 300 ms, so 400 covers it.
  Future<void> tapRail(WidgetTester tester, AppSection section) async {
    await tester.tap(railButtonFor(section));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Every screen under test, the section it belongs to, and how narrow it
  /// may be pumped.
  ///
  /// The last three entries are the interesting ones: DNS sits two levels
  /// under Routing, the diagnostics frame is shared by four tab routes, and
  /// appearance is a leaf of Settings. None of them is a destination of its
  /// own, and each has to light its parent.
  ///
  /// [compact] is 420 everywhere except the routing screen, whose rule rows
  /// overflow below roughly 500 dp. That is a pre-existing defect of the row,
  /// not of the shell — at this width the body is the same tree it has always
  /// been, because `MobileShell` drops destinations on the floor — so the
  /// screen is pumped at the 560 its own test uses rather than having an
  /// unrelated overflow silenced here.
  final screens =
      <({String name, Widget screen, AppSection section, double compact})>[
    (
      name: 'home',
      screen: const HomeScreen(),
      section: AppSection.home,
      compact: 420,
    ),
    (
      name: 'routing',
      screen: const RoutingScreen(),
      section: AppSection.routing,
      compact: 560,
    ),
    (
      name: 'DNS',
      screen: const DnsScreen(),
      section: AppSection.routing,
      compact: 420,
    ),
    (
      name: 'diagnostics',
      screen: const DiagnosticsShell(
        route: AppRoutes.diagnosticsLogs,
        child: SizedBox.shrink(),
      ),
      section: AppSection.diagnostics,
      compact: 420,
    ),
    (
      name: 'appearance',
      screen: const AppearanceScreen(),
      section: AppSection.settings,
      compact: 420,
    ),
  ];

  group('below the first breakpoint', () {
    for (final entry in screens) {
      testWidgets('${entry.name} shows no rail at all', (tester) async {
        await pumpAt(tester, entry.screen, width: entry.compact);

        expect(find.byType(MobileShell), findsOneWidget);
        expect(find.byType(TabletShell), findsNothing);
        expect(find.byType(DesktopShell), findsNothing);
        expect(railButtons(), findsNothing);
      });
    }

    testWidgets('the cog is still the way into settings', (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 420);

      // One cog, in the app bar, exactly as before. The home screen now names
      // a Settings destination as well, and on a phone that has to stay
      // invisible.
      expect(find.byIcon(CommyIcons.settings), findsOneWidget);
    });

    testWidgets('the back arrow is still the way out of a section',
        (tester) async {
      await pumpAt(tester, const DnsScreen(), width: 420);

      expect(find.byIcon(CommyIcons.chevronLeft), findsOneWidget);
    });

    /// The whole phone contract, at both ends of the range and at the edge.
    ///
    /// 420 is the width the rest of this file argues at, and one width is not
    /// a range: the breakpoint is 600, so 599 is where a comparison written
    /// the wrong way round first shows, and 320 is the narrowest screen the
    /// app claims to run on. Android is the release platform (CLAUDE.md §1),
    /// which is why the phone gets the loop and the tablet gets the argument.
    for (final width in <int>[320, 420, 599]) {
      testWidgets('$width dp is the screen it always was', (tester) async {
        await pumpAt(
          tester,
          const HomeScreen(),
          width: width.toDouble(),
          height: 900,
          nodes: <ProxyNode>[
            testNode(),
            testNode(id: 'node-2', name: 'Warsaw 01', countryCode: 'PL'),
          ],
        );

        expect(find.byType(MobileShell), findsOneWidget);
        expect(railButtons(), findsNothing);
        // Hero at the top of the one list, the two app bar controls, and a
        // chip that still opens the picker: the four things the two wide
        // layouts move, none of which may move here.
        expect(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(HeroArea),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(CommyIcons.add), findsOneWidget);
        expect(find.byIcon(CommyIcons.settings), findsOneWidget);
        expect(
          tester.widget<SelectedNode>(find.byType(SelectedNode)).onTap,
          isNotNull,
        );
      });
    }
  });

  group('medium, 700 dp', () {
    for (final entry in screens) {
      testWidgets('${entry.name} lights ${entry.section.name} in the rail',
          (tester) async {
        await pumpAt(tester, entry.screen, width: 700);

        expect(find.byType(TabletShell), findsOneWidget);
        expect(railButtons(), findsNWidgets(AppSection.values.length));
        expect(selectedRailLabel(tester), entry.section.label(t));
      });
    }

    testWidgets('the shell is handed the four sections, in one order',
        (tester) async {
      await pumpAt(tester, const DnsScreen(), width: 700);

      final shell = tester.widget<TabletShell>(find.byType(TabletShell));
      expect(
        shell.destinations.map((destination) => destination.label),
        <String>[
          t.home.title,
          t.settings.routing,
          t.settings.diagnostics,
          t.settings.title,
        ],
      );
      expect(shell.selectedIndex, AppSection.routing.index);
    });

    testWidgets('the rail names its sections without drawing the names',
        (tester) async {
      await pumpAt(tester, const DnsScreen(), width: 700);

      // Icons only between the breakpoints: the name is carried by the
      // tooltip and by the accessible label, never by a word on screen.
      expect(find.text(t.home.title), findsNothing);
      expect(
        tester
            .widgetList<CommyIconButton>(railButtons())
            .map((button) => button.semanticLabel),
        containsAll(<String>[t.home.title, t.settings.title]),
      );
    });
  });

  group('expanded, 1100 dp', () {
    testWidgets('the sidebar spells every section out', (tester) async {
      await pumpAt(tester, const DnsScreen(), width: 1100);

      expect(find.byType(DesktopShell), findsOneWidget);
      for (final section in AppSection.values) {
        expect(
          find.text(section.label(t)),
          findsOneWidget,
          reason: 'At 1100 dp there is room to say ${section.name} out loud.',
        );
      }
    });

    testWidgets('a nested screen still selects its parent section',
        (tester) async {
      await pumpAt(tester, const DnsScreen(), width: 1100);

      final shell = tester.widget<DesktopShell>(find.byType(DesktopShell));
      expect(shell.selectedIndex, AppSection.routing.index);
      expect(
        shell.onDestinationSelected,
        isNotNull,
        reason: 'A sidebar nothing can be chosen from is decoration.',
      );
    });
  });

  /// Where the rail actually goes.
  ///
  /// The groups above ask the shell what it was handed: four labels, in one
  /// order, with the right one lit. None of them presses anything, so a
  /// destination wired to the wrong route — or to none — would pass every one
  /// of them. These press.
  group('the rail goes where it says', () {
    testWidgets('Routing leaves the home screen for it', (tester) async {
      await pumpRouterAt(tester, width: 700);
      expect(find.byType(HomeScreen), findsOneWidget);

      await tapRail(tester, AppSection.routing);

      expect(find.byType(RoutingScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(selectedRailLabel(tester), t.settings.routing);
    });

    testWidgets('Diagnostics lands on the log tab, not on a hub',
        (tester) async {
      await pumpRouterAt(tester, width: 700);

      await tapRail(tester, AppSection.diagnostics);

      // `AppSection.diagnostics` names `AppRoutes.diagnosticsLogs` rather
      // than the hub, because the hub is a redirect to it. A rail entry that
      // goes through the redirect works too — until the redirect changes.
      expect(find.byType(DiagnosticsShell), findsOneWidget);
      expect(
        router.state.uri.toString(),
        AppRoutes.diagnosticsLogs,
      );
    });

    testWidgets('a rail tap switches places rather than stacking them',
        (tester) async {
      await pumpRouterAt(tester, width: 700);

      await tapRail(tester, AppSection.routing);
      await tapRail(tester, AppSection.settings);

      // `go`, not `push`. Two taps that pushed would leave Home under
      // Routing under Settings, and the back arrow — which every section
      // wires to its own parent — would be undoing a history of clicks.
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(
        router.canPop(),
        isFalse,
        reason: 'The rail is a place switcher, not a history.',
      );
    });

    testWidgets('below the breakpoint there is no rail to tap', (tester) async {
      await pumpRouterAt(tester, width: 420);

      // The same router, the same screens, the same destinations named — and
      // nothing drawn from them. This is the phone contract in one assertion.
      expect(railButtons(), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  /// Part 2: the home screen's own two panes.
  ///
  /// docs/05-ux-flows.md asks for «детали в правой панели» from 600 dp and
  /// spells the wide case out — «Двухпанельная компоновка: список слева,
  /// детали справа». Here the list is the servers and their subscription
  /// cards, and the detail is the connection: the disc, the status and the
  /// chosen server. All of it used to be one `ListView`, so a 1100 dp window
  /// put the connect button alone on a wide band with the servers below the
  /// fold.
  ///
  /// The widths below are not arbitrary. Both wide shells drop a detail pane
  /// rather than squeeze it, so two panes need
  /// [CommySizes.detailPaneMinWidth] twice over *beside* the navigation: 809
  /// dp with the rail, 981 with the sidebar. 700 is therefore a real case and
  /// not a degenerate one — a window wide enough for the rail and too narrow
  /// for a second pane — and what it must do is keep the column it had.
  group('the home screen splits into two panes', () {
    /// Two servers, because one is not a choice: over a single server the chip
    /// draws no chevron at any width, and these tests are about the width.
    List<ProxyNode> twoServers() => <ProxyNode>[
          testNode(),
          testNode(id: 'node-2', name: 'Warsaw 01', countryCode: 'PL'),
        ];

    /// The hero drawn inside the server list, which is the single column.
    Finder heroInList() => find.descendant(
          of: find.byType(ListView),
          matching: find.byType(HeroArea),
        );

    testWidgets('at 900 the connection is the pane and the servers the body',
        (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 900);

      expect(
        tester.widget<TabletShell>(find.byType(TabletShell)).detail,
        isNotNull,
      );
      // The hero left the list without leaving the screen.
      expect(find.byType(HeroArea), findsOneWidget);
      expect(heroInList(), findsNothing);
      expect(find.byType(NodeTile), findsOneWidget);
      expect(
        tester.getCenter(find.byType(HeroArea)).dx,
        greaterThan(tester.getCenter(find.byType(NodeTile)).dx),
        reason: 'The list is the left pane, the connection the right one.',
      );
    });

    testWidgets('at 1100 the same split, with the sidebar taking its 260',
        (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 1100);

      expect(
        tester.widget<DesktopShell>(find.byType(DesktopShell)).detail,
        isNotNull,
      );
      expect(find.byType(HeroArea), findsOneWidget);
      expect(heroInList(), findsNothing);
      expect(
        tester.getCenter(find.byType(HeroArea)).dx,
        greaterThan(tester.getCenter(find.byType(NodeTile)).dx),
      );
      // The hero fills the pane rather than shrinking to the width of the
      // widest thing in it: the disc is meant to be centred in a column, not
      // huddled in one.
      expect(
        tester.getSize(find.byType(HeroArea)).width,
        CommySizes.detailPaneMinWidth,
      );
    });

    testWidgets(
        'at 700 the rail leaves no room for a pane, so the column '
        'stays whole', (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 700);

      // 700 less the rail is 611, and two panes want 720. A detail handed
      // over here would be dropped by the shell, and with it the connect
      // button — so the screen keeps the hero where it has always been.
      expect(
        tester.widget<TabletShell>(find.byType(TabletShell)).detail,
        isNull,
      );
      expect(heroInList(), findsOneWidget);
      expect(find.byType(ConnectButton), findsOneWidget);
    });

    testWidgets('at 420 the hero is still the top of the one list',
        (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 420);

      expect(find.byType(MobileShell), findsOneWidget);
      expect(heroInList(), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(HeroArea)).dy,
        lessThan(tester.getTopLeft(find.byType(NodeTile)).dy),
        reason: 'Hero first, then the servers — the phone is unchanged.',
      );
    });

    testWidgets('the chip keeps its picker in one column', (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 420, nodes: twoServers());

      expect(
        tester.widget<SelectedNode>(find.byType(SelectedNode)).onTap,
        isNotNull,
      );
    });

    testWidgets('the chip keeps its picker beside a list pane', (tester) async {
      await pumpAt(
        tester,
        const HomeScreen(),
        width: 1100,
        nodes: twoServers(),
      );

      // The chevron promises a list at every width. Beside a pane the rows
      // are on screen already, and the picker is still the shorter way: it
      // opens under the button, narrowed to the chosen subscription.
      expect(
        tester.widget<SelectedNode>(find.byType(SelectedNode)).onTap,
        isNotNull,
      );
    });

    testWidgets(
        'the search, the order chip and the empty state stay with '
        'the list', (tester) async {
      await pumpAt(
        tester,
        const HomeScreen(),
        width: 1100,
        nodes: <ProxyNode>[
          testNode(),
          testNode(id: 'node-2', name: 'Warsaw 01', countryCode: 'PL'),
        ],
      );

      expect(find.byType(SearchField), findsOneWidget);
      expect(find.byType(CommyChip), findsOneWidget);
      expect(heroInList(), findsNothing);

      await tester.enterText(find.byType(SearchField), 'zzz');
      await settle(tester);

      // "Nothing found" is the list pane's answer. The connection pane is not
      // part of the question, so the disc is still there to be pressed.
      expect(find.text(t.home.search.nothing), findsOneWidget);
      expect(find.byType(ConnectButton), findsOneWidget);
    });

    testWidgets('a tunnel failure explains itself beside the disc it reddened',
        (tester) async {
      // 460 dp of height is a desktop window dragged short, and the pane
      // gets all of it: hero, then banner. A column that could not scroll
      // overflows at this height, which in a test is an exception rather than
      // a stripe.
      await pumpAt(
        tester,
        const HomeScreen(),
        width: 1100,
        height: 460,
        status: const TunnelStatus.error(CommyFailure.permissionDenied()),
      );

      expect(find.text(t.error.permissionDenied.message), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(FailureBanner),
        ),
        findsNothing,
        reason: 'The cause belongs with the disc, not on top of the servers.',
      );
      expect(
        tester.getCenter(find.byType(FailureBanner)).dx,
        greaterThan(tester.getCenter(find.byType(NodeTile)).dx),
      );
    });

    testWidgets('a first run with nothing to list gets no pane either',
        (tester) async {
      await pumpAt(
        tester,
        const HomeScreen(),
        width: 1100,
        nodes: <ProxyNode>[],
      );

      // Deliberate, and the reason is the same one the first-run view is
      // built on: there is no list to put a detail beside, and a disc with
      // nothing behind it is a button that cannot keep its promise. The
      // onboarding owns the whole width — docs/05-ux-flows.md, «Пустое
      // состояние само по себе объясняет, что делать».
      expect(
        tester.widget<DesktopShell>(find.byType(DesktopShell)).detail,
        isNull,
      );
      expect(find.byType(ConnectButton), findsNothing);
      expect(find.text(t.home.empty.title), findsOneWidget);
    });

    testWidgets('the skeleton owns the whole width until the store answers',
        (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 1100, settled: false);

      // The screen does not know yet whether there is anything to connect to,
      // and a disc drawn in a pane the first-run view is about to take away
      // would be a promise made before the store answered.
      expect(
        tester.widget<DesktopShell>(find.byType(DesktopShell)).detail,
        isNull,
      );
      expect(find.byType(CommySkeleton), findsWidgets);
    });

    testWidgets('a window dragged across the breakpoint keeps the disc',
        (tester) async {
      // A tablet turned on its side, or a desktop window dragged narrow. The
      // hero has to change places without going missing on the way: the pane
      // stops being drawn at 700 and the list has to take it back, and the
      // list has to give it up again on the way out.
      await pumpAt(tester, const HomeScreen(), width: 900);
      expect(heroInList(), findsNothing);

      tester.view.physicalSize = const Size(700, 1600);
      await settle(tester);

      expect(find.byType(ConnectButton), findsOneWidget);
      expect(heroInList(), findsOneWidget);
      expect(
        tester.widget<TabletShell>(find.byType(TabletShell)).detail,
        isNull,
      );

      tester.view.physicalSize = const Size(900, 1600);
      await settle(tester);

      expect(find.byType(ConnectButton), findsOneWidget);
      expect(heroInList(), findsNothing);
    });
  });

  /// The home app bar's controls, across all three shells.
  ///
  /// The app bar is handed to the shell, so a screen that starts choosing
  /// between shells is a screen that can lose what it put in there. The `+`
  /// is the one that must survive that choice: outside the first-run view it
  /// is the only way to import anything, and on the two wide layouts the app
  /// bar sits over the list pane alone, which is one more place for it to go
  /// missing. Nothing draws a second `+`, so it is asserted at every width.
  ///
  /// The cog is the opposite case, and it is the one that changed.
  /// docs/05-ux-flows.md gives the header the sections below 600 dp and the
  /// navigation everything from 600 up — so from the first breakpoint the
  /// rail already carries Settings, and a cog beside it was a second door
  /// into the same room. The screen now offers it only where there is no rail
  /// to carry it.
  group('the app bar across the widths', () {
    /// The bar's own buttons: everything the rail did not draw.
    Finder barButton(IconData icon) => find.byWidgetPredicate(
          (widget) =>
              widget is CommyIconButton &&
              widget.icon == icon &&
              widget.size != CommySizes.iconNav,
        );

    for (final width in <int>[420, 700, 900, 1100]) {
      testWidgets('the + is there at $width dp', (tester) async {
        await pumpAt(tester, const HomeScreen(), width: width.toDouble());

        expect(barButton(CommyIcons.add), findsOneWidget);
      });
    }

    /// 600 is the breakpoint itself, where a comparison written the wrong way
    /// round would first show; 700 and 900 are the widths the file already
    /// argues at. 1100 is a shell further on and gets its own case below.
    for (final width in <int>[600, 700, 900]) {
      testWidgets('at $width dp the rail carries settings, not the bar',
          (tester) async {
        await pumpAt(tester, const HomeScreen(), width: width.toDouble());

        // The screen stops handing the cog over rather than the shell hiding
        // it, so the only Settings on screen is the one the navigation draws.
        expect(barButton(CommyIcons.settings), findsNothing);
        expect(railButtonFor(AppSection.settings), findsOneWidget);
      });
    }

    testWidgets('at 1100 dp the sidebar carries it, spelled out',
        (tester) async {
      await pumpAt(tester, const HomeScreen(), width: 1100);

      // `DesktopShell` writes the section names rather than drawing the rail's
      // icon buttons, so the entry is found by its word, not by its size.
      expect(barButton(CommyIcons.settings), findsNothing);
      expect(find.text(t.settings.title), findsOneWidget);
    });
  });
}
