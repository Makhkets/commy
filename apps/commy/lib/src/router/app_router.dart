import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/config_screen.dart';
import 'package:commy/src/screens/diagnostics/connections_screen.dart';
import 'package:commy/src/screens/diagnostics/logs_screen.dart';
import 'package:commy/src/screens/diagnostics/stats_screen.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/settings/about_screen.dart';
import 'package:commy/src/screens/settings/appearance_screen.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The router.
///
/// Flat, on purpose. There is no `ShellRoute` and no navigation bar to keep
/// alive: on a phone the sections are pushed and popped, and on a tablet or a
/// desktop the rail is drawn by `AdaptiveScaffold` inside each screen rather
/// than by the router. A shell would force one navigation model on all three
/// widths, which docs/05-ux-flows.md explicitly calls a mistake in both
/// directions.
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
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.routing,
        builder: (context, state) => const RoutingScreen(),
      ),
      GoRoute(
        path: AppRoutes.appearance,
        builder: (context, state) => const AppearanceScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        builder: (context, state) => const AboutScreen(),
      ),
      // `/settings/diagnostics` is the path the settings list uses; it has no
      // screen of its own because the hub *is* the log tab.
      GoRoute(
        path: AppRoutes.diagnostics,
        redirect: (context, state) => AppRoutes.diagnosticsLogs,
      ),
      GoRoute(
        path: AppRoutes.diagnosticsLogs,
        builder: (context, state) => const LogsScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsConnections,
        builder: (context, state) => const ConnectionsScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsConfig,
        builder: (context, state) => const ConfigScreen(),
      ),
      GoRoute(
        path: AppRoutes.diagnosticsStats,
        builder: (context, state) => const StatsScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
