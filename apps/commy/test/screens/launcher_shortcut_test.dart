import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy/src/screens/import/qr_scan_sheet.dart';
import 'package:commy/src/state/system_intent_listener.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../support/commy_test_app.dart';
import '../support/fake_scanner.dart';

/// The launcher icon's long-press entries (AppShortcuts.kt): each opens the
/// app with an event, and the home screen answers it with the sheet.
void main() {
  const link = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality#Amsterdam%2003';

  late MobileScannerPlatform original;
  late FakeScanner scanner;

  setUp(() {
    original = MobileScannerPlatform.instance;
    scanner = FakeScanner();
    MobileScannerPlatform.instance = scanner;
  });

  tearDown(() async {
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
    await scanner.close();
  });

  Future<CommyTestHarness> pumpHome(
    WidgetTester tester, {
    String? clipboard,
  }) async {
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final harness = CommyTestHarness(
      nodes: <ProxyNode>[testNode()],
      clipboard: clipboard,
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
    );
    await settle(tester);
    return harness;
  }

  void raise(WidgetTester tester, SystemIntentKind kind) {
    ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    ).read(pendingShortcutProvider.notifier).offer(kind);
  }

  testWidgets('"Import from clipboard" opens the paste sheet with it',
      (tester) async {
    await pumpHome(tester, clipboard: '  $link\n');

    raise(tester, SystemIntentKind.paste);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final sheet = tester.widget<PasteSheet>(find.byType(PasteSheet));
    expect(sheet.initialText, link);
  });

  testWidgets('with nothing on the clipboard the sheet opens empty',
      (tester) async {
    await pumpHome(tester);

    raise(tester, SystemIntentKind.paste);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final sheet = tester.widget<PasteSheet>(find.byType(PasteSheet));
    expect(sheet.initialText, isNull);
  });

  testWidgets('"Scan a QR code" opens the scanner', (tester) async {
    await pumpHome(tester);

    raise(tester, SystemIntentKind.scan);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(QrScanSheet), findsOneWidget);
  });

  testWidgets('a shortcut is answered once', (tester) async {
    await pumpHome(tester);

    raise(tester, SystemIntentKind.scan);
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
      listen: false,
    );
    expect(container.read(pendingShortcutProvider), isNull);
  });
}
