import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_router.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/dns_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/commy_test_app.dart';

/// The system Back, on the app's own router.
///
/// Found on the emulator: Settings, Back — and the launcher. The routes were
/// flat siblings, so `go` left one page on the stack and Android's Back had
/// nothing to pop but the app itself. On a phone that gesture is used far more
/// than any arrow drawn on the screen.
void main() {
  late CommyTestHarness harness;
  late GoRouter router;

  Future<void> pumpApp(WidgetTester tester) async {
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

  /// Goes to [location] the way the app does, with `go`.
  Future<void> go(WidgetTester tester, String location) async {
    router.go(location);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// What Android sends when the user presses Back or swipes from the edge.
  Future<bool> systemBack(WidgetTester tester) async {
    final handled = await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return handled;
  }

  testWidgets('Back from settings returns home instead of closing the app',
      (tester) async {
    await pumpApp(tester);
    await go(tester, AppRoutes.settings);
    expect(find.byType(SettingsScreen), findsOneWidget);

    final handled = await systemBack(tester);

    expect(handled, isTrue, reason: 'Unhandled is the app closing.');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Back walks DNS → routing → settings → home', (tester) async {
    await pumpApp(tester);
    await go(tester, AppRoutes.dns);
    expect(find.byType(DnsScreen), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(RoutingScreen), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await systemBack(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('Back from a diagnostics tab lands on settings', (tester) async {
    await pumpApp(tester);
    await go(tester, AppRoutes.diagnostics);
    expect(find.byType(LogsScreen), findsOneWidget);

    // Switching tabs replaces the tab rather than stacking another one.
    await go(tester, AppRoutes.diagnosticsStats);
    await systemBack(tester);

    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('Back on the home screen is the one that leaves', (tester) async {
    await pumpApp(tester);

    final handled = await systemBack(tester);

    expect(handled, isFalse);
  });
}
