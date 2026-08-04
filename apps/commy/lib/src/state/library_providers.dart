/// What the user owns: servers, subscriptions, settings and routing.
///
/// Every one of these is a live stream out of the repository, so a write in
/// one screen shows up in another without anybody wiring a refresh.
library;

import 'package:commy/src/di/repository_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every stored server, in display order.
final nodesProvider = StreamProvider<List<ProxyNode>>((ref) {
  return ref.watch(nodeRepositoryProvider).watchAll();
});

/// Hand-made groups (a subscription is not one of these).
final nodeGroupsProvider = StreamProvider<List<NodeGroup>>((ref) {
  return ref.watch(nodeRepositoryProvider).watchGroups();
});

/// Every stored subscription, in the order they were added.
final subscriptionsProvider = StreamProvider<List<Subscription>>((ref) {
  return ref.watch(subscriptionRepositoryProvider).watchAll();
});

/// Application settings.
final settingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watch();
});

/// Routing policy: mode, rules, per-app selection.
final routingPolicyProvider = StreamProvider<RoutingPolicy>((ref) {
  return ref.watch(routingRepositoryProvider).watch();
});

/// DNS settings.
final dnsSettingsProvider = StreamProvider<DnsSettings>((ref) {
  return ref.watch(routingRepositoryProvider).watchDns();
});

/// Whether unreachable servers are currently kept out of the lists.
///
/// docs/05-ux-flows.md is precise about this: "**timeout** не прячет узел:
/// сервер мог быть временно недоступен. Скрытие нерабочих — отдельный
/// переключатель." So a server that failed a probe stays visible until the
/// user asks otherwise, and the filter lives behind `AppSettings`.
final nodeFilterProvider = Provider<NodeFilter>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return NodeFilter(
    hideUnavailable: settings?.hideUnavailable ?? false,
  );
});

/// Applies the "hide unavailable" setting to a list of servers.
@immutable
class NodeFilter {
  /// Creates the filter.
  const NodeFilter({required this.hideUnavailable});

  /// Whether servers that failed their last probe are dropped.
  final bool hideUnavailable;

  /// Whether [node] is shown.
  ///
  /// A node nobody has measured yet counts as reachable: it has not failed,
  /// it simply has not been asked. Hiding it would make a fresh import look
  /// like a broken one.
  bool isVisible(ProxyNode node) =>
      !hideUnavailable || node.latency != null || node.lastCheckedAt == null;

  /// [nodes] with the hidden ones removed.
  List<ProxyNode> apply(List<ProxyNode> nodes) {
    if (!hideUnavailable) {
      return nodes;
    }
    return <ProxyNode>[
      for (final node in nodes)
        if (isVisible(node)) node,
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeFilter && other.hideUnavailable == hideUnavailable;

  @override
  int get hashCode => hideUnavailable.hashCode;
}

/// Nodes that came from a paste, a QR code or a file rather than a panel.
///
/// The per-subscription split is deliberately **not** a provider family. The
/// home screen already holds the whole list, and a family would recompute and
/// re-notify one card per stored subscription on every latency write.
final manualNodesProvider = Provider<List<ProxyNode>>((ref) {
  final all = ref.watch(nodesProvider).value ?? const <ProxyNode>[];
  return <ProxyNode>[
    for (final node in all)
      if (!node.isFromSubscription) node,
  ];
});

/// The node the user picked, or `null` before the first pick.
///
/// Kept in a notifier rather than derived from settings because the selection
/// is written through two different paths — `ConnectUseCase` on a cold start
/// and `SwitchNodeUseCase` on a live switch — and the screen must not flicker
/// while the write lands.
final selectedNodeIdProvider =
    AsyncNotifierProvider<SelectedNodeIdController, String?>(
  SelectedNodeIdController.new,
);

/// Reads and writes the selected node id.
class SelectedNodeIdController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final repository = ref.watch(settingsRepositoryProvider);
    final result = await repository.readSelectedNodeId();
    return result.valueOrNull;
  }

  /// Remembers [nodeId] as the current selection.
  ///
  /// The state moves first so the list highlight follows the tap immediately;
  /// a storage failure surfaces as an error state rather than a silent revert.
  Future<void> select(String? nodeId) async {
    state = AsyncData<String?>(nodeId);
    final result =
        await ref.read(settingsRepositoryProvider).writeSelectedNodeId(nodeId);
    final failure = result.failureOrNull;
    if (failure != null) {
      state = AsyncError<String?>(failure, StackTrace.current);
    }
  }
}

/// The currently selected node, resolved against the stored list.
final selectedNodeProvider = Provider<ProxyNode?>((ref) {
  final id = ref.watch(selectedNodeIdProvider).value;
  if (id == null) {
    return null;
  }
  final all = ref.watch(nodesProvider).value ?? const <ProxyNode>[];
  for (final node in all) {
    if (node.id == id) {
      return node;
    }
  }
  return null;
});
