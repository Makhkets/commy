import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/mappers/node_group_mapper.dart';
import 'package:commy_data/src/mappers/node_mapper.dart';
import 'package:commy_data/src/mappers/subscription_mapper.dart';
import 'package:commy_data/src/secure/secret_vault.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Replaces the whole library — subscriptions, groups, servers — at once.
///
/// Built on the same order `DriftNodeRepository.replaceForSubscription` uses,
/// for the same reason: the database is transactional and secure storage is
/// not. So new credentials go into the keystore first, then every row changes
/// in one drift batch, then credentials nobody owns any more are removed. A
/// failure before or in the batch leaves the old library whole, and puts back
/// the old credentials under any id the backup shares with it (restoring onto
/// the same phone reuses them all); a failure after it leaves the new library
/// whole with some stale entries. Neither leaves a server with credentials
/// that are not its own.
///
/// It touches only the library. The installation id, the database key,
/// traffic history, settings, routing and DNS are someone else's — which is
/// why this is not `SecretVault.wipe()` plus `CommyDatabase.clearAll()`:
/// those would take the HWID and the database key with them.
class DriftLibraryStore implements LibraryStore {
  /// Creates the store.
  DriftLibraryStore({
    required CommyDatabase database,
    required SecretVault secrets,
  })  : _db = database,
        _secrets = secrets;

  final CommyDatabase _db;
  final SecretVault _secrets;

  @override
  Future<
      Result<
          ({
            List<Subscription> subscriptions,
            List<NodeGroup> groups,
            List<ProxyNode> nodes,
          }),
          CommyFailure>> readLibrary() {
    return StorageGuard.run(() async {
      // Unlike the repositories, a keystore that cannot be read fails the
      // read: see LibraryStore.readLibrary.
      final secrets = _unwrap(await _secrets.readAllSubscriptionSecrets());
      final urls = secrets.urls;
      final params = _unwrap(await _secrets.readAllNodeParams());
      final subscriptionRows = await (_db.select(_db.subscriptionRows)
            ..orderBy(<OrderClauseGenerator<$SubscriptionRowsTable>>[
              (table) => OrderingTerm(expression: table.sortIndex),
            ]))
          .get();
      final groupRows = await (_db.select(_db.nodeGroupRows)
            ..orderBy(<OrderClauseGenerator<$NodeGroupRowsTable>>[
              (table) => OrderingTerm(expression: table.sortIndex),
            ]))
          .get();
      final nodeRows = await (_db.select(_db.nodeRows)
            ..orderBy(<OrderClauseGenerator<$NodeRowsTable>>[
              (table) => OrderingTerm(expression: table.sortIndex),
            ]))
          .get();
      // A keystore that answers can still have lost entries — a reset of the
      // platform keystore returns an empty store rather than an error, and a
      // corrupt entry decodes to nothing. A row that says it has a secret and
      // has none would go into the backup without it, looking complete.
      final lost = subscriptionRows
              .where((row) => !urls.containsKey(row.id))
              .length +
          nodeRows
              .where(
                (row) =>
                    row.secretRef != null && (params[row.id]?.isEmpty ?? true),
              )
              .length;
      if (lost > 0) {
        throw StateError('$lost credentials are missing from the keystore');
      }
      return (
        subscriptions: <Subscription>[
          for (final row in subscriptionRows)
            SubscriptionMapper.toDomain(
              row,
              url: urls[row.id],
              page: secrets.pages[row.id],
            ),
        ],
        groups: groupRows.map(NodeGroupMapper.toDomain).toList(),
        nodes: <ProxyNode>[
          for (final row in nodeRows)
            NodeMapper.toDomain(
              row,
              secretParams: params[row.id] ?? const <String, Object?>{},
            ),
        ],
      );
    });
  }

  @override
  Future<Result<void, CommyFailure>> replaceLibrary({
    required List<Subscription> subscriptions,
    required List<NodeGroup> groups,
    required List<ProxyNode> nodes,
  }) {
    return StorageGuard.runVoid(() async {
      final oldNodeIds =
          (await _db.select(_db.nodeRows).get()).map((row) => row.id).toSet();
      final oldSubscriptionIds = (await _db.select(_db.subscriptionRows).get())
          .map((row) => row.id)
          .toSet();
      // What the keystore holds now under the ids about to be overwritten —
      // restoring onto the same phone reuses every id — so a failed batch
      // can hand the old library its own credentials back.
      final oldParams = _unwrap(await _secrets.readAllNodeParams());
      final oldSecrets = _unwrap(await _secrets.readAllSubscriptionSecrets());

      // Credentials first. A row whose secret never landed is a server that
      // fails later with no hint why; a secret whose row never landed is
      // litter, and it is overwritten if the row ever comes.
      try {
        for (final subscription in subscriptions) {
          _rethrowFailure(
            await _secrets.writeSubscriptionUrl(
              subscription.id,
              subscription.url,
            ),
          );
          _rethrowFailure(
            await _secrets.writeSubscriptionPage(
              subscription.id,
              subscription.profileWebPageUrl,
            ),
          );
        }
        for (final node in nodes) {
          _rethrowFailure(
            await _secrets.writeNodeParams(
              node.id,
              NodeMapper.secretsOf(node),
            ),
          );
        }
        await _replaceRows(subscriptions, groups, nodes);
      } on Object {
        await _putBack(
          subscriptions: subscriptions,
          nodes: nodes,
          oldUrls: oldSecrets.urls,
          oldPages: oldSecrets.pages,
          oldParams: oldParams,
        );
        rethrow;
      }

      // Not fatal, as in replaceForSubscription: the library is already
      // replaced, and failing now would tell the user it was not. What is
      // left is an unreachable blob in the keystore, not a leak (R2).
      final keptNodes = nodes.map((node) => node.id).toSet();
      await _secrets.deleteNodeParamsAll(
        oldNodeIds.where((id) => !keptNodes.contains(id)),
      );
      final keptSubscriptions =
          subscriptions.map((subscription) => subscription.id).toSet();
      for (final id in oldSubscriptionIds) {
        if (!keptSubscriptions.contains(id)) {
          await _secrets.deleteSubscriptionUrl(id);
        }
      }
    });
  }

  /// One batch is one transaction. Deletes before inserts, parents before
  /// children: the node table's foreign keys cascade off both parents, so the
  /// node delete is implied, and spelled out anyway so the batch does not
  /// lean on a PRAGMA to be correct.
  Future<void> _replaceRows(
    List<Subscription> subscriptions,
    List<NodeGroup> groups,
    List<ProxyNode> nodes,
  ) {
    return _db.batch((batch) {
      batch
        ..deleteAll(_db.nodeRows)
        ..deleteAll(_db.subscriptionRows)
        ..deleteAll(_db.nodeGroupRows)
        ..insertAll(
          _db.nodeGroupRows,
          groups.map(NodeGroupMapper.toCompanion).toList(),
        )
        ..insertAll(
          _db.subscriptionRows,
          subscriptions.map(SubscriptionMapper.toCompanion).toList(),
        )
        ..insertAll(
          _db.nodeRows,
          nodes.map(NodeMapper.toCompanion).toList(),
        );
    });
  }

  /// After a failed replace: the old library's credentials back under its
  /// ids, and nothing left behind under ids only the backup had. Best effort
  /// — a keystore that just failed may fail again — and never thrown from:
  /// the caller is already reporting the first failure.
  Future<void> _putBack({
    required List<Subscription> subscriptions,
    required List<ProxyNode> nodes,
    required Map<String, Uri> oldUrls,
    required Map<String, Uri> oldPages,
    required Map<String, Map<String, Object?>> oldParams,
  }) async {
    for (final subscription in subscriptions) {
      final old = oldUrls[subscription.id];
      await (old == null
          ? _secrets.deleteSubscriptionUrl(subscription.id)
          : _secrets.writeSubscriptionUrl(subscription.id, old));
      await _secrets.writeSubscriptionPage(
        subscription.id,
        oldPages[subscription.id],
      );
    }
    for (final node in nodes) {
      final old = oldParams[node.id];
      await (old == null
          ? _secrets.deleteNodeParams(node.id)
          : _secrets.writeNodeParams(node.id, old));
    }
  }

  static T _unwrap<T>(Result<T, CommyFailure> result) {
    switch (result) {
      case Ok(:final value):
        return value;
      case Err(:final failure):
        _rethrowFailure(Err<void, CommyFailure>(failure));
        throw StateError('unreachable');
    }
  }

  static void _rethrowFailure(Result<void, CommyFailure> result) {
    final failure = result.failureOrNull;
    if (failure == null) {
      return;
    }
    if (failure is StorageFailure) {
      // Re-thrown as-is so the StorageGuard around the call rebuilds an
      // identical StorageFailure rather than a second-hand one.
      // ignore: only_throw_errors
      throw failure.cause;
    }
    throw StateError('secure storage failed: ${failure.code}');
  }
}
