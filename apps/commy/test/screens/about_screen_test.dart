import 'dart:io';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/screens/settings/about_screen.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/commy_test_app.dart';

/// Queue item #16. The About screen is the only page that answers "what did I
/// install": the version, the sing-box release inside it, the licence it
/// inherits, where the source is, and whether the database file on this build
/// is encrypted.
///
/// Every one of those is a claim about the product rather than a decoration,
/// so what is protected here is that each of them comes from the thing it
/// names — the package the composition root read, the version the descriptor
/// carries, the status the database reported — and lands in the row that
/// announces it, rather than merely appearing somewhere on the page. The one
/// outgoing action on the screen happens on a tap and nowhere else (rule R1).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t = Translations();

  // url_launcher has no registered platform implementation in a test, so the
  // plugin falls back to its method channel and this stands in for the
  // browser.
  const launcher = MethodChannel('plugins.flutter.io/url_launcher');

  final calls = <MethodCall>[];
  var canLaunch = true;

  late CommyTestHarness harness;

  setUp(() {
    calls.clear();
    canLaunch = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, (call) async {
      calls.add(call);
      return switch (call.method) {
        'canLaunch' => canLaunch,
        'launch' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(launcher, null);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AppInfo info = AppInfo.unknown,
    DatabaseEncryptionStatus encryption = DatabaseEncryptionStatus.unavailable,
  }) async {
    // Taller than the 800x600 default: the card, four rows and the storage
    // banner do not fit, and a banner scrolled off screen would read as a
    // banner that is not there.
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    harness = CommyTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(
        const AboutScreen(),
        extra: <Override>[
          appInfoProvider.overrideWithValue(info),
          databaseEncryptionProvider.overrideWithValue(encryption),
        ],
      ),
    );
    await settle(tester);
  }

  /// The row a title sits in.
  ///
  /// Every assertion about a value goes through this: four rows on one screen
  /// each showing a version-shaped string, and a value found merely somewhere
  /// on the page would let two of them swap without a test noticing.
  Finder rowTitled(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(SettingsTile),
      );

  Finder valueIn(String title, String value) => find.descendant(
        of: rowTitled(title),
        matching: find.text(value),
      );

  testWidgets('says what Commy is not, where a user goes to look it up',
      (tester) async {
    await pumpScreen(tester);

    // Not a slogan: no servers of ours, no bundled configs, no accounts and no
    // backend is the constraint the whole product is built under, and this
    // screen is where it is stated.
    expect(find.text(t.app.name), findsOneWidget);
    expect(find.text(t.about.notAService), findsOneWidget);
  });

  testWidgets('shows the version the composition root read from the package',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'Commy',
      packageName: 'net.commy.app',
      version: '0.1.0',
      buildNumber: '42',
      buildSignature: '',
    );
    final package = await PackageInfo.fromPlatform();

    // `main()` builds the descriptor from the plugin exactly like this and
    // hands it down as an override; a widget test cannot call `main()`, so the
    // same two fields are mapped here to pin the shape the row renders.
    await pumpScreen(
      tester,
      info: AppInfo(
        version: package.version,
        build: package.buildNumber,
        coreVersion: AppInfo.singBoxVersion,
      ),
    );

    expect(valueIn(t.about.version, '0.1.0 (42)'), findsOneWidget);
  });

  testWidgets('names the sing-box release the descriptor carries',
      (tester) async {
    // Deliberately not `AppInfo.singBoxVersion`: the default descriptor
    // carries that constant, so a row that printed the constant instead of
    // reading `info.coreVersion` would look right on every build until the
    // day the two disagreed — which is the only day this row matters.
    await pumpScreen(
      tester,
      info: const AppInfo(version: '0.1.0', build: '42', coreVersion: '9.9.9'),
    );

    expect(
      valueIn(t.about.core, t.about.coreValue(version: '9.9.9')),
      findsOneWidget,
    );
    expect(
      find.text(t.about.coreValue(version: AppInfo.singBoxVersion)),
      findsNothing,
    );
  });

  test('the core version the screen shows is the one the Go module pins', () {
    // Rule R8: the core is bumped in its own change. This is the assertion
    // that makes a forgotten constant loud instead of shipping an About screen
    // that names a release the binary is not.
    final source = _goModule().readAsStringSync();
    final pinned = RegExp(r'github\.com/sagernet/sing-box v(\S+)')
        .firstMatch(source)
        ?.group(1);

    expect(
      pinned,
      isNotNull,
      reason: 'sing-box is not required in core/go.mod',
    );
    expect(AppInfo.singBoxVersion, pinned);
  });

  testWidgets('names the licence and opens the full list on tap',
      (tester) async {
    const info = AppInfo(version: '0.1.0', build: '42', coreVersion: '1.0.0');
    await pumpScreen(tester, info: info);

    // GPL-3.0-or-later is inherited from sing-box, not chosen per release.
    expect(valueIn(t.about.licences, t.about.licence), findsOneWidget);

    await tester.tap(find.text(t.about.licences));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final page = find.byType(LicensePage);
    expect(page, findsOneWidget);
    // The licence page carries the same build the row above it does: a
    // licence list for an unnamed version is not evidence of anything.
    expect(
      find.descendant(of: page, matching: find.text(info.fullVersion)),
      findsOneWidget,
    );
  });

  testWidgets('opens the sources outside the app, and only when asked',
      (tester) async {
    await pumpScreen(tester);

    expect(
      find.descendant(
        of: rowTitled(t.about.sources),
        matching: find.text(AppInfo.repository.host),
      ),
      findsOneWidget,
    );
    // Rule R1: rendering the screen asks nobody for anything.
    expect(calls, isEmpty);

    await tester.tap(find.text(t.about.sources));
    await tester.pumpAndSettle();

    expect(
      calls.map((call) => call.method).toList(),
      <String>['canLaunch', 'launch'],
    );
    // The link the user was shown is the link that was opened, in full: the
    // row shows only the host, so nothing else on screen would give away a
    // launch pointed somewhere near it.
    expect(
      calls.first.arguments,
      containsPair('url', AppInfo.repository.toString()),
    );
    final launch = calls.last.arguments as Map<Object?, Object?>;
    expect(launch['url'], AppInfo.repository.toString());
    // In the system browser, not in a web view Commy would then own: an
    // in-app browser inside a privacy tool is a second network surface.
    expect(launch['useWebView'], isFalse);
  });

  testWidgets('a platform that cannot open the link is not asked to',
      (tester) async {
    canLaunch = false;
    await pumpScreen(tester);

    await tester.tap(find.text(t.about.sources));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method).toList(), <String>['canLaunch']);
  });

  testWidgets('a build that cannot encrypt the database file says so',
      (tester) async {
    await pumpScreen(tester);

    // docs/adr/0007 accepts a plain database file for 1.0. It does not accept
    // being quiet about it, and the sentence also says where the secrets are.
    expect(find.text(t.about.storageDegraded), findsOneWidget);
    // Stated, not alarmed about: an accepted limitation drawn in the error
    // tone would teach people to ignore the tone that means something.
    expect(
      tester.widget<ErrorBanner>(find.byType(ErrorBanner)).tone,
      CommyTone.info,
    );
  });

  testWidgets('an encrypted build does not warn about nothing', (tester) async {
    await pumpScreen(tester, encryption: DatabaseEncryptionStatus.encrypted);

    expect(find.text(t.about.storageDegraded), findsNothing);
    expect(find.byType(ErrorBanner), findsNothing);
  });

  testWidgets('every status that is not "encrypted" is warned about',
      (tester) async {
    // The screen tests `!= encrypted` rather than listing the failures, so a
    // status added to the enum is covered by construction — as long as this
    // file keeps checking the whole enum rather than the two it was written
    // against.
    for (final status in DatabaseEncryptionStatus.values) {
      await pumpScreen(tester, encryption: status);
      expect(
        find.text(t.about.storageDegraded),
        status == DatabaseEncryptionStatus.encrypted
            ? findsNothing
            : findsOneWidget,
        reason: 'status ${status.name}',
      );
    }
  });
}

/// `core/go.mod`, found by walking up from wherever the runner started.
File _goModule() {
  var directory = Directory.current;
  while (true) {
    final candidate = File('${directory.path}/core/go.mod');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      fail('core/go.mod is not above ${Directory.current.path}');
    }
    directory = parent;
  }
}
