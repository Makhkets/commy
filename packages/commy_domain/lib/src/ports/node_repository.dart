import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_group.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';

/// Storage of nodes and of the manual groups they can belong to.
///
/// Implementations split the data in two (rule R2): the plain database holds
/// the metadata, the secure storage holds everything inside
/// `ProxyNode.secretParamKeys`. Callers see one whole node.
abstract interface class NodeRepository {
  /// Every node, in display order, refreshed on every change.
  Stream<List<ProxyNode>> watchAll();

  /// Every node, once.
  Future<Result<List<ProxyNode>, CommyFailure>> getAll();

  /// One node, or `null` when there is no such id.
  Future<Result<ProxyNode?, CommyFailure>> findById(String id);

  /// Nodes belonging to [subscriptionId], in the order the panel gave them.
  Future<Result<List<ProxyNode>, CommyFailure>> findBySubscription(
    String subscriptionId,
  );

  /// Inserts or updates [nodes] in one transaction.
  Future<Result<void, CommyFailure>> upsertAll(List<ProxyNode> nodes);

  /// Removes one node and its secrets.
  Future<Result<void, CommyFailure>> deleteById(String id);

  /// Removes every node of a subscription and their secrets.
  Future<Result<void, CommyFailure>> deleteBySubscription(
    String subscriptionId,
  );

  /// Replaces the nodes of [subscriptionId] with [nodes].
  ///
  /// One transaction, so a failed refresh cannot leave the list half updated.
  /// Implementations keep the id of a node whose address and protocol did not
  /// change, so latency history and the current selection survive.
  Future<Result<void, CommyFailure>> replaceForSubscription({
    required String subscriptionId,
    required List<ProxyNode> nodes,
  });

  /// Records the outcome of a latency measurement.
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  });

  /// Rewrites the display order from the given id sequence.
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds);

  /// Manual groups, refreshed on every change.
  Stream<List<NodeGroup>> watchGroups();

  /// Inserts or updates a manual group.
  Future<Result<void, CommyFailure>> upsertGroup(NodeGroup group);

  /// Removes a manual group and, with it, its nodes.
  Future<Result<void, CommyFailure>> deleteGroup(String id);
}
