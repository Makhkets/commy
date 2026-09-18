/// What the user owns: servers, subscriptions, settings and routing.
///
/// Every one of these is a live stream out of the repository, so a write in
/// one screen shows up in another without anybody wiring a refresh.
library;

import 'package:commy/src/di/repository_providers.dart';
import 'package:commy_config/commy_config.dart';
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

/// The rule sets currently on disk.
final ruleSetsProvider = StreamProvider<List<RuleSet>>((ref) {
  return ref.watch(ruleSetRepositoryProvider).watch();
});

/// Where those files live, once the platform has said.
///
/// Read by the configuration generator, which writes the path into the
/// document the core loads out of process.
final ruleSetDirectoryProvider = FutureProvider<String?>((ref) async {
  final result = await ref.watch(ruleSetRepositoryProvider).directory();
  return result.valueOrNull;
});

/// DNS settings.
final dnsSettingsProvider = StreamProvider<DnsSettings>((ref) {
  return ref.watch(routingRepositoryProvider).watchDns();
});

/// What the lists show, and in which order.
///
/// docs/05-ux-flows.md is precise about the first part: "**timeout** не прячет
/// узел: сервер мог быть временно недоступен. Скрытие нерабочих — отдельный
/// переключатель." So a server that failed a probe stays visible until the
/// user asks otherwise, and that switch lives behind `AppSettings`, as does
/// the order. The search text does not: it is what the user typed a moment
/// ago, not a preference.
final nodeFilterProvider = Provider<NodeFilter>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return NodeFilter(
    hideUnavailable: settings?.hideUnavailable ?? false,
    sort: settings?.nodeSort ?? NodeSort.panel,
    query: ref.watch(nodeQueryProvider),
  );
});

/// How the servers inside each list are ordered.
final nodeSortProvider = Provider<NodeSort>((ref) {
  return ref.watch(settingsProvider).value?.nodeSort ?? NodeSort.panel;
});

/// The text in the search field above the lists; empty when there is none.
///
/// A provider rather than field state so that every card, the "nothing found"
/// state and the field itself read one value — and so that a reset from that
/// state reaches the field.
final nodeQueryProvider = NotifierProvider<NodeQuery, String>(NodeQuery.new);

/// Holds the search text.
class NodeQuery extends Notifier<String> {
  @override
  String build() => '';

  /// Replaces the text. Surrounding whitespace is not part of a search.
  void write(String value) => state = value.trim();

  /// Drops the text.
  void clear() => state = '';
}

/// Decides which servers a list shows, and in what order.
@immutable
class NodeFilter {
  /// Creates the filter.
  const NodeFilter({
    required this.hideUnavailable,
    this.sort = NodeSort.panel,
    this.query = '',
  });

  /// Whether servers that failed their last probe are dropped.
  final bool hideUnavailable;

  /// The order inside each list.
  final NodeSort sort;

  /// What the user typed into the search field; empty for no search.
  final String query;

  /// Whether a search is narrowing the lists.
  bool get isSearching => query.isNotEmpty;

  /// Whether [node] answered its last probe, or has not been asked yet.
  ///
  /// A node nobody has measured counts as reachable: it has not failed, it
  /// simply has not been asked. Hiding it would make a fresh import look
  /// like a broken one.
  static bool isReachable(ProxyNode node) =>
      node.latency != null || node.lastCheckedAt == null;

  /// Whether [node] matches the search text.
  ///
  /// Name and host are searched as substrings. The country code has to match
  /// whole: "de" is a country, not two letters that happen to sit inside
  /// "Amsterdam".
  ///
  /// The code is the one the row draws its flag from — [NodeLabel] — so a
  /// server a panel marked with nothing but a flag emoji is still found by
  /// typing its country.
  bool matches(ProxyNode node) {
    if (query.isEmpty) {
      return true;
    }
    final needle = query.toLowerCase();
    return node.name.toLowerCase().contains(needle) ||
        node.host.toLowerCase().contains(needle) ||
        NodeLabel.of(node).countryCode?.toLowerCase() == needle;
  }

  /// Whether [node] is shown.
  bool isVisible(ProxyNode node) =>
      (!hideUnavailable || isReachable(node)) && matches(node);

  /// [nodes] with the hidden ones removed, in [sort] order.
  List<ProxyNode> apply(List<ProxyNode> nodes) {
    return sort.apply(<ProxyNode>[
      for (final node in nodes)
        if (isVisible(node)) node,
    ]);
  }

  /// How many of [nodes] the "hide unavailable" setting takes out.
  ///
  /// Counted without the search, so the footer that reports the number does
  /// not blame the setting for servers a search term left out.
  int hiddenUnavailable(List<ProxyNode> nodes) {
    if (!hideUnavailable) {
      return 0;
    }
    return nodes.where((node) => !isReachable(node)).length;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeFilter &&
          other.hideUnavailable == hideUnavailable &&
          other.sort == sort &&
          other.query == query;

  @override
  int get hashCode => Object.hash(hideUnavailable, sort, query);
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

/// Whether the core picks the server instead of the user.
///
/// The same two conditions the configuration builder applies, asked of the
/// same source: `SingBoxConfigBuilder.usesAutoGroup`. Screens must not invent
/// their own version of this test — an app that shows Auto as the active
/// choice while the document has no such group offers a choice the core
/// cannot honour.
final autoSelectedProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final nodes = ref.watch(nodesProvider).value ?? const <ProxyNode>[];
  return SingBoxConfigBuilder.usesAutoGroup(
    autoSelect: settings?.autoSelect ?? false,
    nodeCount: nodes.length,
  );
});

/// The server whose row is marked as the active one, or `null` when none is.
///
/// Deliberately not the same question as "what is stored". On Auto the core
/// chooses, and the stored id is only the server the list leads with — marking
/// it would tell the user their traffic is on a server that may well not be
/// carrying any. Every list in the app asks this, not the selection.
final activeNodeIdProvider = Provider<String?>((ref) {
  if (ref.watch(autoSelectedProvider)) {
    return null;
  }
  return ref.watch(selectedNodeIdProvider).value;
});

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
