import 'package:commy_domain/src/entities/proxy_node.dart';

/// How the servers inside one list are ordered on screen.
///
/// Applied per list — inside one subscription card, inside the manual group —
/// and never across them. docs/05-ux-flows.md keeps subscriptions in the order
/// they were added, and a sort that reached across cards would put a server
/// under a panel it does not belong to.
enum NodeSort {
  /// As the panel gave them, or as the user arranged them. The default.
  panel,

  /// Fastest first.
  ///
  /// Servers nobody has measured yet follow the measured ones: they have not
  /// failed, they have not been asked. Servers that failed their last probe
  /// come last.
  latency,

  /// By name, case-insensitive.
  name;

  /// [nodes] in this order.
  ///
  /// Stable: two servers the order cannot tell apart keep their panel order,
  /// so switching to [latency] on a list nobody has measured changes nothing
  /// rather than shuffling it.
  List<ProxyNode> apply(List<ProxyNode> nodes) {
    switch (this) {
      case NodeSort.panel:
        return nodes;
      case NodeSort.latency:
        return _stableSorted(nodes, _byLatency);
      case NodeSort.name:
        return _stableSorted(nodes, _byName);
    }
  }

  static int _byLatency(ProxyNode a, ProxyNode b) {
    final byBucket = _latencyBucket(a).compareTo(_latencyBucket(b));
    if (byBucket != 0) {
      return byBucket;
    }
    final left = a.latency;
    final right = b.latency;
    if (left == null || right == null) {
      return 0;
    }
    return left.compareTo(right);
  }

  /// 0 measured, 1 never asked, 2 asked and did not answer.
  static int _latencyBucket(ProxyNode node) {
    if (node.latency != null) {
      return 0;
    }
    return node.lastCheckedAt == null ? 1 : 2;
  }

  static int _byName(ProxyNode a, ProxyNode b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  /// `List.sort` makes no promise about equal elements; this one does.
  static List<ProxyNode> _stableSorted(
    List<ProxyNode> nodes,
    int Function(ProxyNode, ProxyNode) compare,
  ) {
    final order = List<int>.generate(nodes.length, (index) => index)
      ..sort((a, b) {
        final byKey = compare(nodes[a], nodes[b]);
        return byKey != 0 ? byKey : a.compareTo(b);
      });
    return <ProxyNode>[for (final index in order) nodes[index]];
  }
}
