import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Open connections: host, matched rule, outbound, volume, age.
///
/// This tab exists to answer one question — "why is this site going around the
/// proxy" — and the rule column is the answer. Everything else is context.
class ConnectionsScreen extends ConsumerWidget {
  /// Creates the screen.
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider);
    final now = ref.watch(clockProvider).value ?? DateTime.now();
    final isTunnelUp =
        ConnectState.of(ref.watch(tunnelStatusProvider)).isTunnelUp;

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsConnections,
      child: AsyncSection<List<ConnectionInfo>>(
        value: connections,
        skeleton: const ListSkeleton(rows: 6),
        onRetry: () => ref.invalidate(connectionsProvider),
        builder: (context, all) => _Body(
          connections: all,
          now: now,
          isTunnelUp: isTunnelUp,
          onConnect: () => context.go(AppRoutes.home),
          onRefresh: () => ref.invalidate(connectionsProvider),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.connections,
    required this.now,
    required this.isTunnelUp,
    required this.onConnect,
    required this.onRefresh,
  });

  final List<ConnectionInfo> connections;
  final DateTime now;

  /// Whether the core is running, which decides what "empty" means.
  final bool isTunnelUp;

  /// Leads to the connect button.
  final VoidCallback onConnect;

  /// Asks the core for a fresh snapshot.
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    if (connections.isEmpty) {
      // With the tunnel down there is nothing to list, and the way out is
      // the connect button. With it up the list is merely quiet, and asking
      // the core again is the honest action.
      return EmptyState(
        icon: CommyIcons.offline,
        title: t.diagnostics.connectionsEmpty,
        message: t.diagnostics.connectionsEmptyBody,
        actionLabel:
            isTunnelUp ? t.diagnostics.refresh : t.diagnostics.goConnect,
        onAction: isTunnelUp ? onRefresh : onConnect,
      );
    }
    return ListView.separated(
      itemCount: connections.length,
      separatorBuilder: (context, index) => const CommyDivider(),
      itemBuilder: (context, index) {
        final connection = connections[index];
        return ConnectionRow(
          connection: connection,
          age: connection.ageAt(now),
        );
      },
    );
  }
}
