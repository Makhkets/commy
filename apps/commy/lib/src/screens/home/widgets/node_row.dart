import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/node_menu_sheet.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/node_descriptors.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One server in the list.
///
/// Tapping it never disconnects. When the tunnel is up the controller swaps
/// the outbound inside the running core, which is the difference between
/// changing servers and losing every open connection.
///
/// A node that timed out is dimmed but stays in the list: a server that did
/// not answer one probe is not a server that is gone, and hiding it is a
/// separate, explicit setting (docs/05-ux-flows.md).
///
/// Long-pressing opens [NodeMenuSheet]. It used to measure the node directly,
/// which left copying its link and deleting it with nowhere to be; measuring
/// is now the first row of that menu.
class NodeRow extends ConsumerWidget {
  /// Creates the row.
  const NodeRow({required this.node, required this.isActive, super.key});

  /// What joins the descriptor parts, and the subscription subtitle parts.
  static const String separator = ' · ';

  /// The server.
  final ProxyNode node;

  /// Whether this is the chosen server.
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    return NodeTile(
      name: node.name,
      descriptors: NodeDescriptors.of(node),
      latency: node.latency,
      countryCode: node.countryCode,
      isActive: isActive,
      isReachable: node.latency != null || node.lastCheckedAt == null,
      offlineSemanticLabel: t.a11y.offline,
      onTap: () => unawaited(
        ref.read(tunnelControllerProvider.notifier).selectNode(node),
      ),
      onLongPress: () => unawaited(
        NodeMenuSheet.show(context: context, node: node),
      ),
    );
  }
}
