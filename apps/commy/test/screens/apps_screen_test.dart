import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/settings/apps_screen.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #12. The mode, the package list and the `include_package` the
/// configuration ends up with have all existed since the first release; the
/// only missing pieces were the platform call that says which apps are
/// installed and a screen to tick them in.
void main() {
  final t = Translations();

  const firefox = InstalledApp(
    packageName: 'org.mozilla.firefox',
    label: 'Firefox',
  );
  const telegram = InstalledApp(
    packageName: 'org.telegram.messenger',
    label: 'Telegram',
  );
  const settings = InstalledApp(
    packageName: 'com.android.settings',
    label: 'Settings',
    isSystem: true,
  );

  late CommyTestHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<InstalledApp> apps = const <InstalledApp>[firefox, telegram, settings],
    RoutingPolicy? policy,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    if (policy != null) {
      await harness.routingRepository.write(policy);
    }
    await tester.pumpWidget(
      harness.wrap(
        const AppsScreen(),
        extra: <Override>[
          installedAppsProvider.overrideWith((ref) async => apps),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  RoutingPolicy stored() => harness.routingRepository.policy;

  testWidgets('lists the user apps and hides the system ones by default',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    // Forty Google packages between the user and their browser is not a list.
    expect(find.text('Settings'), findsNothing);

    final label = t.apps.showSystem;

    // The switch, not the label: rows in this app put the control on the
    // trailing edge and do not make the whole row a second way to hit it.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is CommySwitch && widget.semanticLabel == label,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('shows Commy itself, greyed, with the reason', (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.apps.self), findsOneWidget);
    expect(find.text(t.apps.selfHint), findsOneWidget);
    final control = tester.widget<CommyCheckbox>(
      find.byType(CommyCheckbox).first,
    );
    expect(control.value, isFalse);
    // Disabled, not absent: an absence explains nothing, and this is the one
    // exclusion the user cannot change.
    expect(control.onChanged, isNull);
  });

  testWidgets('the mode is one control with one explanation', (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.apps.modeDisabledHint), findsOneWidget);

    await tester.tap(find.text(t.apps.modeInclude));
    await tester.pumpAndSettle();

    expect(stored().perAppMode, PerAppMode.include);
    expect(find.text(t.apps.modeIncludeHint), findsOneWidget);
    expect(find.text(t.apps.modeDisabledHint), findsNothing);
  });

  testWidgets('ticking an app stores its package', (tester) async {
    await pumpScreen(tester);

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Firefox'),
          matching: find.byType(Row),
        ).first,
        matching: find.byType(CommyCheckbox),
      ),
    );
    await tester.pumpAndSettle();

    expect(stored().perAppPackages, <String>['org.mozilla.firefox']);
    expect(find.text(t.apps.chosen(count: 1).toUpperCase()), findsOneWidget);
  });

  testWidgets('unticking removes it and leaves the rest in order',
      (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        perAppMode: PerAppMode.include,
        perAppPackages: const <String>[
          'org.mozilla.firefox',
          'org.telegram.messenger',
        ],
      ),
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Firefox'),
          matching: find.byType(Row),
        ).first,
        matching: find.byType(CommyCheckbox),
      ),
    );
    await tester.pumpAndSettle();

    // The order of what is left does not move: a set that reshuffled would
    // read as a change to `ReloadUseCase` and restart the core for nothing.
    expect(stored().perAppPackages, <String>['org.telegram.messenger']);
  });

  testWidgets('clearing empties the list in one write', (tester) async {
    await pumpScreen(
      tester,
      policy: RoutingPolicy.defaults.copyWith(
        perAppPackages: const <String>['org.mozilla.firefox'],
      ),
    );

    await tester.tap(find.text(t.apps.selectNone));
    await tester.pumpAndSettle();

    expect(stored().perAppPackages, isEmpty);
    expect(find.text(t.apps.selectNone), findsNothing);
  });

  testWidgets('search narrows by name and by package', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(SearchField), 'telegram');
    await tester.pumpAndSettle();

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Firefox'), findsNothing);

    await tester.enterText(find.byType(SearchField), 'mozilla');
    await tester.pumpAndSettle();

    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Telegram'), findsNothing);
  });

  testWidgets('a search that matches nothing offers a way back',
      (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(SearchField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text(t.apps.nothingFound), findsOneWidget);
    expect(find.text(t.apps.nothingFoundBody), findsOneWidget);
  });

  testWidgets('a platform with no app list says so instead of showing nothing',
      (tester) async {
    await pumpScreen(tester, apps: const <InstalledApp>[]);

    expect(find.text(t.apps.empty), findsOneWidget);
    expect(find.text(t.apps.emptyBody), findsOneWidget);
  });
}
