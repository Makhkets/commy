import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/router/app_sections.dart';
import 'package:commy/src/screens/home/widgets/auto_row.dart';
import 'package:commy/src/screens/home/widgets/first_run_view.dart';
import 'package:commy/src/screens/home/widgets/hero_area.dart';
import 'package:commy/src/screens/home/widgets/list_toolbar.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy/src/screens/home/widgets/subscription_section.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/screens/import/import_sheet.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/state/system_intent_listener.dart';
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
/// On a phone that is one column. From the second breakpoint up it becomes
/// two: the servers and their subscription cards stay the body, and the
/// connection — the disc, the status, the chosen server — moves into the
/// detail pane beside them (docs/05-ux-flows.md: «Двухпанельная компоновка:
/// список слева, детали справа»). Nothing is dropped and nothing is added in
/// the move; the same widgets change places. See [_fitsDetailPane] for when
/// the split is offered at all.
///
/// All four mandatory states live here:
/// skeleton while the first read lands, the first-run panel when there is
/// nothing to connect to, a full failure view when the store itself is
/// broken, and the content below. Only the last of the four has two halves
/// to split — the other three own the whole width at every size.
class HomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final nodes = ref.watch(nodesProvider);
    final subscriptions = ref.watch(subscriptionsProvider);

    // A link tapped in another app lands here. It opens the sheet pre-filled
    // rather than importing on its own: the user has to see what arrived
    // before it becomes a stored server.
    ref.listen<String?>(pendingImportProvider, (previous, next) {
      if (next == null || next.isEmpty) {
        return;
      }
      ref.read(pendingImportProvider.notifier).take();
      ref.read(importControllerProvider.notifier).reset();
      unawaited(PasteSheet.show(context, initialText: next));
    });

    // One decision, handed to both slots: either the connection is a pane of
    // its own and the body is nothing but the list, or the two are the single
    // column they have always been. Deciding it here rather than in each of
    // them is what keeps the hero from being drawn twice — or nowhere.
    final apart = _fitsDetailPane(context) && _hasServers(nodes, subscriptions);

    return AdaptiveScaffold(
      destinations: AppSection.destinationsFor(t),
      selectedIndex: AppSection.home.index,
      onDestinationSelected: (index) => AppSection.select(context, index),
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
      detail: apart ? const _ConnectionPane() : null,
      body: AsyncSection<List<ProxyNode>>(
        value: nodes,
        skeleton: const _HomeSkeleton(),
        onRetry: () => ref.invalidate(nodesProvider),
        // The section's own context is deliberately not used below: an import
        // that lands a server replaces the first-run view with the list, and
        // the sheet that reports that import has to be presented by something
        // that outlives it. This screen's context does; the builder's may not.
        builder: (_, all) {
          final subs = subscriptions.value ?? const <Subscription>[];
          if (all.isEmpty && subs.isEmpty) {
            return FirstRunView(
              onImportFile: () => unawaited(_importFile(context)),
              onPasteAndConnect: (text) =>
                  unawaited(_pasteAndConnect(context, text)),
            );
          }
          return _HomeContent(
            subscriptions: subs,
            nodes: all,
            hasConnectionPane: apart,
          );
        },
      ),
    );
  }

  /// Opens the import sheet with nothing left over from the last import.
  ///
  /// The reset looks redundant now that `ImportSheet.present` clears the
  /// controller when a sheet's route ends, and for every import that finished
  /// inside its sheet it is. It is kept for the two that do not. An import
  /// still running when the sheet is dismissed — a subscription download is
  /// seconds long — writes its result *after* that clear; and one started
  /// from the first-run view finishes with nowhere to report to if this screen
  /// is gone by then. Both leave a result on the controller with no route left
  /// to carry it, and this is the entry point that would open on it.
  void _openImport(BuildContext context, WidgetRef ref) {
    ref.read(importControllerProvider.notifier).reset();
    ref.invalidate(clipboardPreviewProvider);
    unawaited(ImportSheet.show(context));
  }

  /// Picks a config file for the first-run view and reports what it imported.
  Future<void> _importFile(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(importControllerProvider.notifier).importFile();
    if (!context.mounted) {
      // The user left this screen while the picker was open. There is nothing
      // here to report into; [_openImport] drops what was left behind.
      return;
    }
    await _report(
      context,
      container,
      title: Translations.of(context).import.file.title,
    );
  }

  /// The clipboard offer: import what is in the buffer, then connect to it.
  ///
  /// The sixty-second path from docs/00-vision.md compressed into one tap,
  /// which is why a success is not interrupted by a panel: the screen behind
  /// the tap is already turning into the server list and the tunnel is coming
  /// up on it, and that is the report. The outcome is dropped rather than left
  /// on the shared controller for the next sheet to open on.
  Future<void> _pasteAndConnect(BuildContext context, String text) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final importer = container.read(importControllerProvider.notifier);
    final nodeId = await importer.importText(text);
    if (nodeId == null) {
      if (context.mounted) {
        await _report(
          context,
          container,
          title: Translations.of(context).import.title,
        );
      }
      return;
    }
    importer.reset();
    await container.read(tunnelControllerProvider.notifier).connect(
          nodeId: nodeId,
        );
  }

  /// Shows what an import started outside a sheet did.
  ///
  /// The first-run view has no modal of its own, so an import it starts lands
  /// on the shared controller with nothing rendering it: the parse fails and
  /// the screen says nothing at all, and the next sheet opened — a
  /// subscription, say — opens on that stale failure. Presenting the panel the
  /// four sheets already use gives the result the two things it was missing:
  /// something that draws it (count and skipped lines for a success; cause,
  /// action and the route to the logs for a failure) and a route that owns it,
  /// since `ImportSheet.present` clears the controller however the sheet ends.
  Future<void> _report(
    BuildContext context,
    ProviderContainer container, {
    required String title,
  }) {
    final state = container.read(importControllerProvider);
    if (state.outcome == null && state.failure == null) {
      // Nothing was asked for — the file picker was dismissed — so there is
      // nothing to say, and a modal here would be one the user never opened.
      return Future<void>.value();
    }
    return ImportSheet.present(
      context,
      title: title,
      builder: (_) => const ImportResultPanel(),
    );
  }
}

/// Whether the shell will really put a detail pane beside the body here.
///
/// `MobileShell` ignores `detail` outright, and both wide shells drop it
/// rather than squeeze it when what is left beside the rail cannot hold two
/// columns of [CommySizes.detailPaneMinWidth] — "a 200 dp master list next to
/// a 360 dp detail is worse than one pane", as `TabletShell` puts it. Every
/// other screen answers a dropped pane by pushing its detail as a route. Home
/// cannot: its detail is the connect button, and handing that to a slot that
/// gets dropped would take the button off the screen entirely. So the same
/// question is asked here first, in the same tokens, and a window with no
/// room for two panes — 700 dp, once the rail has taken its share — keeps the
/// single column it has always had.
///
/// Both answers are pinned in `adaptive_layout_test.dart`, so a change to the
/// shell's own rule fails a test here instead of losing the disc quietly.
bool _fitsDetailPane(BuildContext context) {
  final layout = context.layoutSize;
  if (layout.isCompact) {
    return false;
  }
  final navigation =
      layout.isExpanded ? CommySizes.sidebarWidth : CommySizes.railWidth;
  final beside = MediaQuery.sizeOf(context).width -
      MediaQuery.paddingOf(context).horizontal -
      navigation -
      CommySizes.dividerThickness;
  return beside >= CommySizes.detailPaneMinWidth * 2;
}

/// Whether the content state is the one on screen.
///
/// Mirrors the conditions the body applies one level down, because the pane
/// beside the body is chosen one level up. A store that is still landing or
/// broken answers `false` — the skeleton and the failure view are the whole
/// screen, not one half of it — and so does a first run: nothing imported
/// means nothing to list *and* nothing to connect to, and a disc offered
/// beside the onboarding would be a button that cannot keep its promise.
bool _hasServers(
  AsyncValue<List<ProxyNode>> nodes,
  AsyncValue<List<Subscription>> subscriptions,
) {
  if (nodes.hasError) {
    return false;
  }
  final all = nodes.value;
  if (all == null) {
    return false;
  }
  return all.isNotEmpty || (subscriptions.value?.isNotEmpty ?? false);
}

/// The connection, as the pane on the other side of the seam.
///
/// The same hero the phone puts at the top of its list, with the banner that
/// explains a tunnel that failed kept next to the disc it turned red. The
/// pane is as tall as the window and the disc is the thing being looked at,
/// so the block sits in the middle of it rather than clinging to the top —
/// and it scrolls, because a short landscape window is exactly where a disc
/// pinned in place overflows.
class _ConnectionPane extends StatelessWidget {
  const _ConnectionPane();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // No callback, so `SelectedNode` drops its chevron: the list
                // the chip used to scroll into view is the pane on the other
                // side of the seam and never leaves the screen, so there is
                // nothing left for a tap to do. A chevron here would promise
                // a picker that is already open.
                HeroArea(onChooseNode: null),
                _TunnelFailureBanner(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// What the tunnel last failed with, or nothing at all.
///
/// The banner reads the *folded* status, not just this app's last action: a
/// core that died on its own has to explain itself too, and that arrives as a
/// `TunnelError` on the status stream with nothing local behind it.
///
/// It is a widget rather than a branch in the list because it is drawn in two
/// places now — under the disc in the connection pane, and between the Auto
/// row and the toolbar in the single column — and the fold from six statuses
/// to one failure, with the retry and the dismissal hanging off it, is worth
/// writing once.
class _TunnelFailureBanner extends ConsumerWidget {
  const _TunnelFailureBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failure = switch (ref.watch(tunnelStatusProvider)) {
      TunnelError(:final failure) => failure,
      TunnelIdle() ||
      TunnelStarting() ||
      TunnelConnected() ||
      TunnelChecking() ||
      TunnelStopping() =>
        null,
    };
    if (failure == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FailureBanner(
          failure: failure,
          onRetry: () => unawaited(
            ref.read(tunnelControllerProvider.notifier).connect(),
          ),
          onDismiss: () =>
              ref.read(tunnelControllerProvider.notifier).clearFailure(),
        ),
        SizedBox(height: context.spacing.s4),
      ],
    );
  }
}

/// The connected-state body: hero area, an error if there is one, the list.
///
/// With a connection pane beside it the first two are already on screen and
/// this is the list alone. The order of the single column is untouched by
/// that: hero, the Auto row, the failure banner, the toolbar, the cards.
class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({
    required this.subscriptions,
    required this.nodes,
    required this.hasConnectionPane,
  });

  final List<Subscription> subscriptions;
  final List<ProxyNode> nodes;

  /// Whether the connection is already drawn beside this list.
  final bool hasConnectionPane;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  /// The list's own controller, so the selected-server chip can reach it.
  ///
  /// `Scrollable.maybeOf` cannot, and that is not a style point: the chip's
  /// callback closes over the context of *this* widget, which sits above the
  /// list rather than inside it, so the lookup walked up past the ListView
  /// and found nothing. The tap did nothing at all.
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final filter = ref.watch(nodeFilterProvider);
    final manual = filter.apply(ref.watch(manualNodesProvider));
    final activeId = ref.watch(activeNodeIdProvider);
    // The same condition the configuration builder applies: with one server
    // there is no group in the document, so there is nothing to offer — and
    // nothing to search or order either.
    final hasChoice = widget.nodes.length > 1;
    // Counted across every list at once so the footer states one number the
    // user can check against, rather than one per card.
    final hidden = filter.hiddenUnavailable(widget.nodes);

    // One card per subscription, each with its own slice of the list. While
    // a search is on, a card with no match is left out: the user is looking
    // for a server, and a panel header with nothing under it is not an answer.
    final cards = <Widget>[];
    var shown = manual.length;
    for (final subscription in widget.subscriptions) {
      final own = filter.apply(<ProxyNode>[
        for (final node in widget.nodes)
          if (node.subscriptionId == subscription.id) node,
      ]);
      shown += own.length;
      if (filter.isSearching && own.isEmpty) {
        continue;
      }
      cards
        ..add(SubscriptionSection(subscription: subscription, nodes: own))
        ..add(SizedBox(height: spacing.s4));
    }

    return ListView(
      controller: _controller,
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        // The two that move: with a pane beside it the list starts at the
        // Auto row. Without one the order is the phone's, unchanged — hero,
        // Auto row, failure banner, toolbar, cards.
        if (!widget.hasConnectionPane) HeroArea(onChooseNode: _scrollToList),
        if (hasChoice) ...<Widget>[
          const AutoRow(),
          SizedBox(height: spacing.s4),
        ],
        if (!widget.hasConnectionPane) const _TunnelFailureBanner(),
        if (hasChoice) ...<Widget>[
          const ListToolbar(),
          SizedBox(height: spacing.s4),
        ],
        ...cards,
        if (manual.isNotEmpty) ...<Widget>[
          GroupHeader(
            title: t.home.manualGroup,
            subtitle: t.home.manualGroupSubtitle,
          ),
          for (final node in manual)
            NodeRow(node: node, isActive: node.id == activeId),
        ],
        // A search that matched nothing is the one empty state this screen
        // did not have, and it gets the action every other one has.
        if (filter.isSearching && shown == 0)
          EmptyState(
            icon: CommyIcons.search,
            title: t.home.search.nothing,
            message: t.home.search.nothingBody,
            actionLabel: t.home.search.clear,
            onAction: ref.read(nodeQueryProvider.notifier).clear,
          ),
        if (hidden > 0) _HiddenFooter(count: hidden),
      ],
    );
  }

  /// The selected-server chip scrolls to the list rather than opening a
  /// picker: the list is already on this screen, and a modal over it would be
  /// the same rows twice.
  ///
  /// Only ever wired up in the single column. With a connection pane the chip
  /// has no callback at all — see [_ConnectionPane].
  void _scrollToList() {
    if (!_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    unawaited(
      position.animateTo(
        _listOffset.clamp(0, position.maxScrollExtent),
        duration: context.motion.base,
        curve: context.motion.baseCurve,
      ),
    );
  }

  /// Roughly the height of the hero area: enough to put the first card under
  /// the app bar without hunting for a render box.
  static const double _listOffset = 360;
}

/// Says how many servers the "hide unavailable" setting took out of the list.
///
/// A filter that silently shrinks the list is how a user concludes their
/// import lost half the servers. The count is shown with the way to undo it,
/// on the screen where the absence is noticed rather than in settings.
class _HiddenFooter extends ConsumerWidget {
  const _HiddenFooter({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.fromLTRB(spacing.s4, spacing.s4, spacing.s4, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              t.home.hiddenCount(count: count),
              style: context.typography.caption.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
          CommyButton(
            label: t.home.showHidden,
            variant: CommyButtonVariant.ghost,
            isCompact: true,
            onPressed: () => unawaited(
              ref
                  .read(settingsControllerProvider.notifier)
                  .setHideUnavailable(enabled: false),
            ),
          ),
        ],
      ),
    );
  }
}

/// The shape of the answer while the first read lands.
///
/// One column at every width, and no pane beside it: the screen does not know
/// yet whether there is anything to connect to, and a disc drawn in a pane
/// that the first-run view is about to take away would be a promise made
/// before the store answered.
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
