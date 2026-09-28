import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_group.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/subscription.dart';

/// The user's servers as one thing: subscriptions, groups and every server.
///
/// The repositories change one row, one subscription at a time. A restore
/// changes all of it, and half of it is worse than none — a phone left with
/// the new subscriptions and the old servers, or neither. So it is one call
/// here, and the implementation makes it one transaction.
abstract interface class LibraryStore {
  /// Everything in the library, credentials included — or a failure.
  ///
  /// Stricter than the repositories' `getAll`, and that is the point. A
  /// screen that cannot read a credential shows the server anyway and fails
  /// later, at connect; a backup that cannot read one must not be written,
  /// because it would look complete and restore servers that do not work.
  Future<
      Result<
          ({
            List<Subscription> subscriptions,
            List<NodeGroup> groups,
            List<ProxyNode> nodes,
          }),
          CommyFailure>> readLibrary();

  /// Replaces every subscription, group and server with these.
  ///
  /// All or nothing for the rows. Credentials live in secure storage, which
  /// is not transactional: the new ones are written before the rows change,
  /// and the old ones are removed after — so a failure leaves the old library
  /// whole, and at worst some unreachable credentials behind, never a server
  /// without its own.
  ///
  /// Every [ProxyNode.subscriptionId] and [ProxyNode.groupId] must name one of
  /// [subscriptions] or [groups]; `BackupSnapshot.fromJson` guarantees it.
  Future<Result<void, CommyFailure>> replaceLibrary({
    required List<Subscription> subscriptions,
    required List<NodeGroup> groups,
    required List<ProxyNode> nodes,
  });
}
