import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsConnections,
      child: AsyncSection<List<ConnectionInfo>>(
        value: connections,
        skeleton: const ListSkeleton(rows: 6),
        onRetry: () => ref.invalidate(connectionsProvider),
        builder: (context, all) => _Body(connections: all, now: now),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.connections, required this.now});

  final List<ConnectionInfo> connections;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    if (connections.isEmpty) {
      return EmptyState(
        icon: CommyIcons.offline,
        title: t.diagnostics.connectionsEmpty,
        message: t.diagnostics.connectionsEmptyBody,
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
