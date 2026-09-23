import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/about_screen.dart';
import 'package:commy/src/screens/settings/appearance_screen.dart';
import 'package:commy/src/screens/settings/apps_screen.dart';
import 'package:commy/src/screens/settings/dns_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/rule_sets_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The router.
///
/// Nested the way [AppRoutes] is spelled: every section sits under the screen
/// it is opened from, so `go` builds the whole back-stack — home, settings,
/// routing, DNS — and the system Back walks it one screen at a time.
///
/// It used to be flat. Every route was a sibling, `go` replaced the stack with
/// a single page, and Back on Android — the gesture people use more than any
/// on-screen arrow — closed the app from every screen but the first. Found on
/// the emulator: Settings, Back, launcher.
///
/// There is still no `ShellRoute` and no navigation bar to keep alive: on a
/// phone the sections are pushed and popped, and on a tablet or a desktop the
/// rail is drawn by `AdaptiveScaffold` inside each screen rather than by the
/// router. A shell would force one navigation model on all three widths,
/// which docs/05-ux-flows.md explicitly calls a mistake in both directions.
///
/// The diagnostics tabs are siblings under settings, not a stack of their
/// own: switching tabs replaces the tab, and Back from any of them goes to
/// settings, which is where the hub is entered from.
///
/// The import sheet is not a route. It is a modal over the screen that opened
/// it, so a failed import can keep the typed text and the screen underneath.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: _child(AppRoutes.settings, of: AppRoutes.home),
            builder: (context, state) => const SettingsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: _child(AppRoutes.routing, of: AppRoutes.settings),
                builder: (context, state) => const RoutingScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: _child(AppRoutes.apps, of: AppRoutes.routing),
                    builder: (context, state) => const AppsScreen(),
                  ),
                  GoRoute(
                    path: _child(AppRoutes.ruleSets, of: AppRoutes.routing),
                    builder: (context, state) => const RuleSetsScreen(),
                  ),
                  GoRoute(
                    path: _child(AppRoutes.dns, of: AppRoutes.routing),
                    builder: (context, state) => const DnsScreen(),
                  ),
                ],
              ),
              GoRoute(
                path: _child(AppRoutes.appearance, of: AppRoutes.settings),
                builder: (context, state) => const AppearanceScreen(),
              ),
              GoRoute(
                path: _child(AppRoutes.about, of: AppRoutes.settings),
                builder: (context, state) => const AboutScreen(),
              ),
              // `/settings/diagnostics` is the path the settings list uses;
              // it has no screen of its own because the hub *is* the log tab.
              GoRoute(
                path: _child(AppRoutes.diagnostics, of: AppRoutes.settings),
                redirect: (context, state) => AppRoutes.diagnosticsLogs,
              ),
              GoRoute(
                path: _child(AppRoutes.diagnosticsLogs, of: AppRoutes.settings),
                builder: (context, state) => const LogsScreen(),
              ),
              GoRoute(
                path: _child(
                  AppRoutes.diagnosticsConnections,
                  of: AppRoutes.settings,
                ),
                builder: (context, state) => const ConnectionsScreen(),
              ),
              GoRoute(
                path: _child(
                  AppRoutes.diagnosticsConfig,
                  of: AppRoutes.settings,
                ),
                builder: (context, state) => const ConfigScreen(),
              ),
              GoRoute(
                path:
                    _child(AppRoutes.diagnosticsStats, of: AppRoutes.settings),
                builder: (context, state) => const StatsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// [path] relative to its parent [of], which is how a nested `GoRoute` spells
/// it. Derived rather than typed a second time, so [AppRoutes] stays the one
/// place a path is written.
String _child(String path, {required String of}) {
  final prefix = of.endsWith('/') ? of : '$of/';
  assert(path.startsWith(prefix), '$path is not under $of');
  return path.substring(prefix.length);
}
