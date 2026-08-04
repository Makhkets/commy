import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/home/widgets/first_run_view.dart';
import 'package:commy/src/screens/home/widgets/hero_area.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy/src/screens/home/widgets/subscription_section.dart';
import 'package:commy/src/screens/import/import_sheet.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/failure_view.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The one root screen.
///
/// Everything the user does day to day is here: the button, the chosen server,
/// and every server they own underneath it. There is no bottom bar and no
/// second "Servers" tab — the decision to connect and the list you pick from
/// are the same screen, which is the argument docs/05-ux-flows.md makes and
/// the reason the list gets the freed height.
///
/// All four mandatory states live here:
/// skeleton while the first read lands, the first-run panel when there is
/// nothing to connect to, a full failure view when the store itself is
/// broken, and the content below.
class HomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final nodes = ref.watch(nodesProvider);
    final subscriptions = ref.watch(subscriptionsProvider);

    return AdaptiveScaffold(
      appBar: CommyAppBar(
        title: t.app.wordmark,
        leading: <Widget>[
          CommyIconButton(
            icon: CommyIcons.settings,
            semanticLabel: t.a11y.settings,
            tooltip: t.settings.title,
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
        actions: <Widget>[
          CommyIconButton(
            icon: CommyIcons.add,
            semanticLabel: t.a11y.addServer,
            tooltip: t.import.title,
            onPressed: () => _openImport(context, ref),
          ),
        ],
      ),
      body: AsyncSection<List<ProxyNode>>(
        value: nodes,
        skeleton: const _HomeSkeleton(),
        onRetry: () => ref.invalidate(nodesProvider),
        builder: (context, all) {
          final subs = subscriptions.value ?? const <Subscription>[];
          if (all.isEmpty && subs.isEmpty) {
            return FirstRunView(onImport: () => _openImport(context, ref));
          }
          return _HomeContent(subscriptions: subs, nodes: all);
        },
      ),
    );
  }

  void _openImport(BuildContext context, WidgetRef ref) {
    ref.read(importControllerProvider.notifier).reset();
    ref.invalidate(clipboardPreviewProvider);
    unawaited(ImportSheet.show(context));
  }
}

/// The connected-state body: hero area, an error if there is one, the list.
class _HomeContent extends ConsumerWidget {
  const _HomeContent({required this.subscriptions, required this.nodes});

  final List<Subscription> subscriptions;
  final List<ProxyNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final manual = ref.watch(manualNodesProvider);
    final selectedId = ref.watch(selectedNodeIdProvider).value;
    // The banner reads the *folded* status, not just this app's last action:
    // a core that died on its own has to explain itself too, and that arrives
    // as a `TunnelError` on the status stream with nothing local behind it.
    final failure = switch (ref.watch(tunnelStatusProvider)) {
      TunnelError(:final failure) => failure,
      TunnelIdle() ||
      TunnelStarting() ||
      TunnelConnected() ||
      TunnelChecking() ||
      TunnelStopping() =>
        null,
    };

    return ListView(
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        HeroArea(onChooseNode: () => _scrollToList(context)),
        if (failure != null) ...<Widget>[
          FailureBanner(
            failure: failure,
            onRetry: () => unawaited(
              ref.read(tunnelControllerProvider.notifier).connect(),
            ),
            onDismiss: () =>
                ref.read(tunnelControllerProvider.notifier).clearFailure(),
          ),
          SizedBox(height: spacing.s4),
        ],
        for (final subscription in subscriptions) ...<Widget>[
          SubscriptionSection(
            subscription: subscription,
            nodes: <ProxyNode>[
              for (final node in nodes)
                if (node.subscriptionId == subscription.id) node,
            ],
          ),
          SizedBox(height: spacing.s4),
        ],
        if (manual.isNotEmpty) ...<Widget>[
          GroupHeader(
            title: t.home.manualGroup,
            subtitle: t.home.manualGroupSubtitle,
          ),
          for (final node in manual)
            NodeRow(node: node, isActive: node.id == selectedId),
        ],
      ],
    );
  }

  /// The selected-server chip scrolls to the list rather than opening a
  /// picker: the list is already on this screen, and a modal over it would be
  /// the same rows twice.
  void _scrollToList(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null) {
      return;
    }
    unawaited(
      position.animateTo(
        position.maxScrollExtent == 0 ? 0 : _listOffset,
        duration: context.motion.base,
        curve: context.motion.baseCurve,
      ),
    );
  }

  /// Roughly the height of the hero area: enough to put the first card under
  /// the app bar without hunting for a render box.
  static const double _listOffset = 360;
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(height: spacing.s6),
        const Center(
          child: CommySkeleton(
            width: CommyConnectTokens.discSize,
            height: CommyConnectTokens.discSize,
            borderRadius: BorderRadius.all(
              Radius.circular(CommyConnectTokens.discSize / 2),
            ),
          ),
        ),
        SizedBox(height: spacing.s5),
        const Center(child: CommySkeleton(width: _chipWidth)),
        SizedBox(height: spacing.s6),
        const Expanded(child: ListSkeleton(hasHeader: true)),
      ],
    );
  }

  static const double _chipWidth = 140;
}
