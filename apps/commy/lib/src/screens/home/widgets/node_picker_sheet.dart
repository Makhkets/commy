import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/auto_row.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The servers of the chosen subscription, one tap from the connect button.
///
/// The chip under the button draws a chevron, and a chevron promises a list.
/// It used to scroll the screen's own list into view instead, which kept that
/// promise only on a phone, only above the fold, and only if the user noticed
/// the page had moved. Now it opens what it says: the servers that came with
/// the chosen one, where the thumb already is.
///
/// Only that subscription, not everything stored. The question asked under
/// the button is "which country of this provider", and a user with three
/// panels does not want ninety rows to answer it — the full list, with its
/// search and its cards, is the screen underneath. Servers added by hand are
/// one another's neighbours the same way. With nothing chosen yet there is no
/// subscription to narrow to, and the sheet shows every server.
///
/// The rows are the very widgets the list uses — [AutoRow], [NodeRow] — so a
/// tap here is the same switch inside the running core, and the active bar,
/// the flag and the latency cannot drift from the list. The search text is
/// deliberately not applied: it belongs to the list it was typed over, and a
/// picker emptied by a query the user cannot see from here would look broken.
class NodePickerSheet extends ConsumerWidget {
  /// Creates the sheet body.
  const NodePickerSheet({
    this.everyServer = false,
    this.connectOnPick = false,
    super.key,
  });

  /// Whether to list every server rather than those of the chosen server's
  /// own subscription. The failure banner asks for it: when a panel is down
  /// all of its servers fail together, and the way out is another panel's.
  final bool everyServer;

  /// Whether a pick also connects. The failure banner asks for it too: a
  /// server picked as the way out of a failed connect is a server to connect
  /// to, and a pick that only moved the selection left the old failure on
  /// screen with nothing happening.
  final bool connectOnPick;

  /// Opens the picker as a bottom sheet, or a dialog on a wide window.
  static Future<void> show(
    BuildContext context, {
    bool everyServer = false,
    bool connectOnPick = false,
  }) {
    return CommySheet.show<void>(
      context: context,
      builder: (context) => NodePickerSheet(
        everyServer: everyServer,
        connectOnPick: connectOnPick,
      ),
    );
  }

  /// Whether there is anything to pick between.
  ///
  /// The same condition the home list uses for its Auto row and toolbar: one
  /// server is not a choice, and a chevron over it would open a list of the
  /// row the chip already names.
  static bool isOffered(List<ProxyNode> nodes) => nodes.length > 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final all = ref.watch(nodesProvider).value ?? const <ProxyNode>[];
    final anchor = everyServer ? null : ref.watch(selectedNodeProvider);
    final activeId = ref.watch(activeNodeIdProvider);
    final settings = ref.watch(settingsProvider).value;

    final scoped = anchor == null
        ? all
        : <ProxyNode>[
            for (final node in all)
              if (node.subscriptionId == anchor.subscriptionId) node,
          ];
    final shown = NodeFilter(
      hideUnavailable: settings?.hideUnavailable ?? false,
      sort: settings?.nodeSort ?? NodeSort.panel,
    ).apply(scoped);

    void close() => Navigator.of(context).pop();

    /// Closes the sheet and, from the failure banner, connects to [nodeId]
    /// — or to whatever Auto picks when it is `null`.
    VoidCallback chosen({String? nodeId}) {
      if (!connectOnPick) {
        return close;
      }
      final tunnel = ref.read(tunnelControllerProvider.notifier);
      return () {
        close();
        unawaited(tunnel.connect(nodeId: nodeId));
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: Semantics(
            header: true,
            child: Text(
              _title(t, ref, anchor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.title2.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
        SizedBox(height: spacing.s3),
        // Bounded, because the surface around it is a column that takes its
        // children's height: forty servers would push the sheet off the top
        // of the screen instead of scrolling.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * _maxHeightShare,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: <Widget>[
              if (isOffered(all)) AutoRow(onChosen: chosen()),
              for (final node in shown)
                NodeRow(
                  node: node,
                  isActive: node.id == activeId,
                  onChosen: chosen(nodeId: node.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whose servers these are: the panel's name, or the manual group's.
  String _title(Translations t, WidgetRef ref, ProxyNode? anchor) {
    if (anchor == null) {
      return t.home.selectNode;
    }
    final subscriptionId = anchor.subscriptionId;
    if (subscriptionId == null) {
      return t.home.manualGroup;
    }
    final subscriptions =
        ref.watch(subscriptionsProvider).value ?? const <Subscription>[];
    for (final subscription in subscriptions) {
      if (subscription.id == subscriptionId) {
        return subscription.name;
      }
    }
    return t.home.selectNode;
  }

  /// How much of the window the list may take before it scrolls.
  ///
  /// A share of the window rather than a spacing token: it is a proportion,
  /// and it has to leave the scrim — the way out — visible above the sheet.
  static const double _maxHeightShare = 0.6;
}
