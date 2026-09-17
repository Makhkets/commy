import 'package:commy_domain/src/entities/proxy_node.dart';

/// Folds entries that name the same server into the single row they become.
///
/// A node's identity leaves the display name out on purpose, so one endpoint
/// listed in two of a panel's groups, or pasted twice under two names, is one
/// server and the store keeps one row for it.
///
/// The fold has two jobs and both want it applied before a write. A store
/// handed two entries under one primary key fails the whole insert, and the
/// user is told their subscription did not update when nothing was wrong with
/// it. A caller that reports the parser's list rather than the store's
/// promises servers that were never kept, and an import is reported once,
/// with no history to correct it afterwards.
abstract final class NodeDuplicates {
  /// [nodes] with every repeated [ProxyNode.id] folded into one entry.
  ///
  /// The last entry wins the fields, the first keeps its place in the list —
  /// where storing the two of them one after another would have left them.
  ///
  /// The result is unmodifiable: callers read it and hand it on. Anything
  /// that needs to sort or extend the list copies it first.
  static List<ProxyNode> folded(List<ProxyNode> nodes) {
    final byId = <String, ProxyNode>{};
    for (final node in nodes) {
      byId[node.id] = node;
    }
    return List<ProxyNode>.unmodifiable(byId.values);
  }
}
