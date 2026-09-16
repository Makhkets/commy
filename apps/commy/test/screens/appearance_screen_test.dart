import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/settings/appearance_screen.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Queue item #16. The appearance screen is the only place the theme and the
/// language are chosen, and neither choice does anything here: `CommyApp`
/// reads `AppSettings.themeMode` for `MaterialApp.themeMode` and listens to
/// `AppSettings.locale` to reload the slang bundle.
///
/// So the assertions worth having are about the value that leaves the screen —
/// the stored theme, the stored tag, and the null that means "ask the device" —
/// rather than about a radio redrawing itself. The second half of that is the
/// label: a row is a promise about what it sets, and the two groups here carry
/// the same "follow the device" sentence, so every label is checked against
/// the value of the radio next to it rather than merely being on the screen.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppSettings settings = AppSettings.defaults,
    List<Override> extra = const <Override>[],
    bool animationsEnd = true,
  }) async {
    // Taller than the 800x600 default: two sections of three rows each, and a
    // surface that cut the language group off would be testing the window.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness(settings: settings);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(const AppearanceScreen(), extra: extra),
    );
    if (animationsEnd) {
      await tester.pumpAndSettle();
    } else {
      await settle(tester);
    }
  }

  Future<AppSettings> stored() async {
    final result = await harness.settingsRepository.read();
    return result.valueOrNull ?? AppSettings.defaults;
  }

  /// The radio standing for [mode]. Found by value, not by label: the
  /// "follow the device" row reads the same in both groups.
  Finder themeRadio(AppThemeMode mode) => find.byWidgetPredicate(
        (widget) => widget is CommyRadio<AppThemeMode> && widget.value == mode,
      );

  Finder localeRadio(String locale) => find.byWidgetPredicate(
        (widget) => widget is CommyRadio<String> && widget.value == locale,
      );

  /// The whole row a radio sits in, which is the second way to pick it.
  Finder rowOf(Finder radio) =>
      find.ancestor(of: radio, matching: find.byType(SettingsTile));

  bool chosen(WidgetTester tester, Finder radio) =>
      tester.widget<CommyRadio<Object>>(radio).isSelected;

  testWidgets('offers one row per theme, each labelled with what it sets',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text(t.appearance.theme.toUpperCase()), findsOneWidget);
    expect(find.text(t.appearance.language.toUpperCase()), findsOneWidget);
    // A mode added to `AppThemeMode` and forgotten here is a theme the app
    // can store and the user cannot reach.
    expect(
      find.byType(CommyRadio<AppThemeMode>),
      findsNWidgets(AppThemeMode.values.length),
    );

    final labels = <AppThemeMode, String>{
      AppThemeMode.system: t.appearance.themeSystem,
      AppThemeMode.light: t.appearance.themeLight,
      AppThemeMode.dark: t.appearance.themeDark,
    };
    // Checked against the enum so that a mode added to the domain fails this
    // file instead of quietly going untested.
    expect(labels.keys, unorderedEquals(AppThemeMode.values));
    for (final entry in labels.entries) {
      // Scoped to the row: a label somewhere on the screen says nothing about
      // which value the radio beside it writes, and the light label wired to
      // `AppThemeMode.dark` is a screen that lies about every tap.
      expect(
        find.descendant(
          of: rowOf(themeRadio(entry.key)),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: 'the row that sets ${entry.key.name} must be labelled '
            '"${entry.value}"',
      );
    }
  });

  testWidgets('offers exactly the languages the bundles can load',
      (tester) async {
    await pumpScreen(tester);

    final offered = <String>[
      for (final radio in tester.widgetList<CommyRadio<String>>(
        find.byType(CommyRadio<String>),
      ))
        radio.value,
    ];

    // The empty string is "follow the device". The rest are tags handed to
    // `LocaleSettings.setLocaleRaw`, so a tag with no bundle behind it is a
    // row that does nothing, and a bundle with no row is dead weight in the
    // build.
    expect(offered, contains(''));
    expect(
      offered.where((locale) => locale.isNotEmpty),
      unorderedEquals(AppLocaleUtils.supportedLocalesRaw),
    );

    // And each tag is behind the name of its own language: a user who picks
    // "English" and gets Russian has no second clue to go on.
    final labels = <String, String>{
      '': t.appearance.languageSystem,
      'ru': t.appearance.languageRu,
      'en': t.appearance.languageEn,
    };
    for (final entry in labels.entries) {
      expect(
        find.descendant(
          of: rowOf(localeRadio(entry.key)),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: 'the row that stores "${entry.key}" must be labelled '
            '"${entry.value}"',
      );
    }
  });

  testWidgets('shows the stored theme and the stored language as chosen',
      (tester) async {
    await pumpScreen(
      tester,
      settings: AppSettings.defaults.copyWith(
        themeMode: AppThemeMode.light,
        locale: 'ru',
      ),
    );

    expect(chosen(tester, themeRadio(AppThemeMode.light)), isTrue);
    expect(chosen(tester, themeRadio(AppThemeMode.system)), isFalse);
    expect(chosen(tester, localeRadio('ru')), isTrue);
    // The two groups are independent. One fed from the other would still look
    // right on the defaults, and only diverge once something was picked.
    expect(chosen(tester, localeRadio('')), isFalse);
  });

  testWidgets('a tap on the row stores the theme', (tester) async {
    await pumpScreen(tester);

    await tester.tap(rowOf(themeRadio(AppThemeMode.dark)));
    await tester.pumpAndSettle();

    expect((await stored()).themeMode, AppThemeMode.dark);
  });

  testWidgets('a tap on the radio stores the theme and comes back',
      (tester) async {
    await pumpScreen(
      tester,
      settings: AppSettings.defaults.copyWith(themeMode: AppThemeMode.dark),
    );

    await tester.tap(themeRadio(AppThemeMode.light));
    await tester.pumpAndSettle();

    expect((await stored()).themeMode, AppThemeMode.light);
    // Redrawn from the stored value, not from a local field: the screen owns
    // no copy of the setting.
    expect(chosen(tester, themeRadio(AppThemeMode.light)), isTrue);
    expect(chosen(tester, themeRadio(AppThemeMode.dark)), isFalse);
  });

  testWidgets('picking a language stores the tag slang reloads with',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(localeRadio('en'));
    await tester.pumpAndSettle();

    final tag = (await stored()).locale;
    expect(tag, 'en');
    expect(AppLocaleUtils.parse(tag!), AppLocale.en);
  });

  testWidgets('a tap on the language row stores the tag as well',
      (tester) async {
    // The row and the radio are two call sites of the same setter, and the
    // row is the one with the whole width of the screen behind it.
    await pumpScreen(tester);

    await tester.tap(rowOf(localeRadio('ru')));
    await tester.pumpAndSettle();

    expect((await stored()).locale, 'ru');
    expect(chosen(tester, localeRadio('ru')), isTrue);
  });

  testWidgets('"match system" clears the tag instead of storing one',
      (tester) async {
    await pumpScreen(
      tester,
      settings: AppSettings.defaults.copyWith(locale: 'en'),
    );

    await tester.tap(localeRadio(''));
    await tester.pumpAndSettle();

    // `CommyApp` calls `useDeviceLocale()` only when the stored tag is null or
    // empty; anything else is handed to `setLocaleRaw`.
    expect((await stored()).locale, isNull);
    expect(chosen(tester, localeRadio('')), isTrue);
  });

  testWidgets('switching the theme leaves every other setting alone',
      (tester) async {
    const seeded = AppSettings(
      locale: 'ru',
      autoConnect: true,
      hideUnavailable: true,
      nodeSort: NodeSort.latency,
      ipCheckUrl: 'https://ip.example.net/json',
      mixedPort: 3080,
      tunStack: TunStack.mixed,
    );
    await pumpScreen(tester, settings: seeded);

    await tester.tap(themeRadio(AppThemeMode.dark));
    await tester.pumpAndSettle();

    // Settings are stored as one envelope and written back whole, so a setter
    // that built its copy from the wrong source would reset the connection and
    // silence screens from a theme tap.
    expect(await stored(), seeded.copyWith(themeMode: AppThemeMode.dark));
  });

  testWidgets('draws the shape of the answer before the settings arrive',
      (tester) async {
    await pumpScreen(
      tester,
      animationsEnd: false,
      extra: <Override>[
        settingsProvider.overrideWith(
          (ref) => Stream<AppSettings>.fromFuture(
            Completer<AppSettings>().future,
          ),
        ),
      ],
    );

    expect(find.byType(ListSkeleton), findsOneWidget);
    // Not the rows with a guessed default ticked: a radio sitting on "system"
    // before the stored value lands is a claim nobody read.
    expect(find.byType(CommyRadio<AppThemeMode>), findsNothing);
  });

  testWidgets('a failure carries a cause, an action and a route to the logs',
      (tester) async {
    await pumpScreen(
      tester,
      extra: <Override>[
        settingsProvider.overrideWith(
          (ref) => Stream<AppSettings>.error(const StorageFailure('disk')),
        ),
      ],
    );

    expect(find.text(t.error.title), findsOneWidget);
    expect(find.text(t.error.storage.message), findsOneWidget);
    expect(find.text(t.error.storage.action), findsOneWidget);
    expect(find.text(t.error.openLogs), findsOneWidget);
    // And nothing pretending to be editable underneath it.
    expect(find.byType(CommyRadio<AppThemeMode>), findsNothing);
  });
}
