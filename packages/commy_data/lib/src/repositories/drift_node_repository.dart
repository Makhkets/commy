import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/mappers/node_group_mapper.dart';
import 'package:commy_data/src/mappers/node_mapper.dart';
import 'package:commy_data/src/secure/secret_vault.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Nodes and manual groups, split across the database and the keystore.
///
/// Callers see whole `ProxyNode`s. Underneath, every write tears the credential
/// parameters out of `params` and sends them to `SecretVault`, and every read
/// puts them back (rule R2). Two ordering rules keep that split honest:
///
/// * on write, secrets go first — a row that exists without its credentials is
///   a node that silently cannot connect, while an orphaned keystore entry is
///   harmless and gets overwritten;
/// * on delete, secrets go first for the same reason in reverse: the row is the
///   index, and losing the index while keeping the secret leaks nothing but
///   leaves litter.
class DriftNodeRepository implements NodeRepository {
  /// Creates the repository.
  DriftNodeRepository({
    required CommyDatabase database,
    required SecretVault secrets,
  })  : _db = database,
        _secrets = secrets;

  final CommyDatabase _db;
  final SecretVault _secrets;

  // ── Nodes ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<ProxyNode>> watchAll() {
    return _orderedNodes().watch().asyncMap(_hydrateAll);
  }

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> getAll() {
    return StorageGuard.run(() async {
      final rows = await _orderedNodes().get();
      return _hydrateAll(rows);
    });
  }

  @override
  Future<Result<ProxyNode?, CommyFailure>> findById(String id) {
    return StorageGuard.run(() async {
      final row = await (_db.select(_db.nodeRows)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        return null;
      }
      final secrets = await _secrets.readNodeParams(id);
      return NodeMapper.toDomain(
        row,
        secretParams: secrets.valueOrNull ?? const <String, Object?>{},
      );
    });
  }

  @override
  Future<Result<List<ProxyNode>, CommyFailure>> findBySubscription(
    String subscriptionId,
  ) {
    return StorageGuard.run(() async {
      final query = _db.select(_db.nodeRows)
        ..where((table) => table.subscriptionId.equals(subscriptionId))
        ..orderBy(<OrderClauseGenerator<$NodeRowsTable>>[
          (table) => OrderingTerm(expression: table.sortIndex),
        ]);
      return _hydrateAll(await query.get());
    });
  }

  @override
  Future<Result<void, CommyFailure>> upsertAll(List<ProxyNode> nodes) {
    return StorageGuard.runVoid(() async {
      for (final node in nodes) {
        await _writeSecrets(node);
      }
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(
          _db.nodeRows,
          nodes.map(NodeMapper.toCompanion).toList(),
        );
      });
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) {
    return StorageGuard.runVoid(() async {
      // Secret first: aborting here leaves the node intact, which is a state
      // the user can retry from. The other order leaves a credential nobody
      // owns any more.
      await _deleteSecrets(<String>[id]);
      await (_db.delete(_db.nodeRows)..where((table) => table.id.equals(id)))
          .go();
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteBySubscription(
    String subscriptionId,
  ) {
    return StorageGuard.runVoid(() async {
      final ids = await _idsWhereSubscription(subscriptionId);
      await _deleteSecrets(ids);
      await (_db.delete(_db.nodeRows)
            ..where((table) => table.subscriptionId.equals(subscriptionId)))
          .go();
    });
  }

  @override
  Future<Result<void, CommyFailure>> replaceForSubscription({
    required String subscriptionId,
    required List<ProxyNode> nodes,
  }) {
    return StorageGuard.runVoid(() async {
      final existing = await (_db.select(_db.nodeRows)
            ..where((table) => table.subscriptionId.equals(subscriptionId)))
          .get();

      // A panel renames and reorders nodes freely; what identifies a server is
      // protocol + host + port. Matching on that keeps the local id, and with
      // it the measured latency and the user's current selection.
      final byEndpoint = <String, NodeRow>{};
      for (final row in existing) {
        byEndpoint.putIfAbsent(NodeMapper.endpointKeyOfRow(row), () => row);
      }

      // One server can appear twice in a perfectly ordinary payload — the same
      // endpoint listed in two of the panel's groups. Both entries arrive under
      // one id, because a node's identity leaves the display name out
      // (`NodeIdFactory`), so they are folded before anything is written: two
      // companions sharing a primary key fail the insert, and the user is told
      // their subscription did not update when nothing was wrong with it.
      final unique = _foldDuplicates(nodes);

      final reusedIds = <String>{};
      final incoming = <ProxyNode>[];
      for (var index = 0; index < unique.length; index++) {
        final node = unique[index];
        final previous = byEndpoint[NodeMapper.endpointKeyOf(node)];
        final carried = previous == null || reusedIds.contains(previous.id)
            ? node
            : node.copyWith(
                id: previous.id,
                latency: previous.latencyMicros == null
                    ? null
                    : Duration(microseconds: previous.latencyMicros!),
                lastCheckedAt: previous.lastCheckedAt,
              );
        if (previous != null) {
          reusedIds.add(previous.id);
        }
        // Positions are handed out after the fold, so a repeat leaves no gap
        // in the order the user scrolls through.
        incoming.add(
          carried.copyWith(subscriptionId: subscriptionId, sortIndex: index),
        );
      }

      final writtenIds = incoming.map((node) => node.id).toSet();
      final droppedIds = existing
          .map((row) => row.id)
          // `writtenIds` on top of `reusedIds`: the keystore is cleaned after
          // the commit, so an id that is about to be stored must never be on
          // that list, whatever the endpoint match concluded (R2).
          .where((id) => !reusedIds.contains(id) && !writtenIds.contains(id))
          .toList();

      // Secure storage is not transactional, so it is updated around the
      // transaction rather than inside it: new credentials first, obsolete
      // ones after the rows they belonged to are gone.
      for (final node in incoming) {
        await _writeSecrets(node);
      }
      // A drift batch is already atomic — it opens its own transaction — so the
      // delete and the inserts go in one, rather than a batch nested inside an
      // explicit transaction.
      await _db.batch((batch) {
        batch
          ..deleteWhere<$NodeRowsTable, NodeRow>(
            _db.nodeRows,
            (table) => table.subscriptionId.equals(subscriptionId),
          )
          // Last write wins, exactly as in `upsertAll`. The delete above has
          // already taken every row of this subscription, so the only conflict
          // left is one payload naming a row twice — and the fold above has
          // settled which of the two the user should end up with.
          ..insertAllOnConflictUpdate(
            _db.nodeRows,
            incoming.map(NodeMapper.toCompanion).toList(),
          );
      });
      // Deliberately not fatal. The refresh has already committed; failing it
      // now would tell the user their subscription did not update when it did.
      // What is left behind is an unreachable blob in the keystore, which is
      // litter rather than a leak, and it is overwritten if the node returns.
      await _secrets.deleteNodeParamsAll(droppedIds);
    });
  }

  @override
  Future<Result<void, CommyFailure>> updateLatency({
    required String id,
    required Duration? latency,
    required DateTime checkedAt,
  }) {
    return StorageGuard.runVoid(() async {
      await (_db.update(_db.nodeRows)..where((table) => table.id.equals(id)))
          .write(
        NodeRowsCompanion(
          latencyMicros: Value<int?>(latency?.inMicroseconds),
          lastCheckedAt: Value<DateTime?>(checkedAt),
        ),
      );
    });
  }

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) {
    return StorageGuard.runVoid(() async {
      await _db.batch((batch) {
        for (var index = 0; index < orderedIds.length; index++) {
          batch.update(
            _db.nodeRows,
            NodeRowsCompanion(sortIndex: Value<int>(index)),
            where: (table) => table.id.equals(orderedIds[index]),
          );
        }
      });
    });
  }

  // ── Manual groups ─────────────────────────────────────────────────────────

  @override
  Stream<List<NodeGroup>> watchGroups() {
    final query = _db.select(_db.nodeGroupRows)
      ..orderBy(<OrderClauseGenerator<$NodeGroupRowsTable>>[
        (table) => OrderingTerm(expression: table.sortIndex),
        (table) => OrderingTerm(expression: table.name),
      ]);
    return query.watch().map(
          (rows) => rows.map(NodeGroupMapper.toDomain).toList(),
        );
  }

  @override
  Future<Result<void, CommyFailure>> upsertGroup(NodeGroup group) {
    return StorageGuard.runVoid(() async {
      await _db
          .into(_db.nodeGroupRows)
          .insertOnConflictUpdate(NodeGroupMapper.toCompanion(group));
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteGroup(String id) {
    return StorageGuard.runVoid(() async {
      // The row cascade takes the nodes; the keystore has no cascade, so their
      // credentials are removed by hand first.
      final ids = await _idsWhereGroup(id);
      await _deleteSecrets(ids);
      await (_db.delete(_db.nodeGroupRows)
            ..where((table) => table.id.equals(id)))
          .go();
    });
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Folds entries that name the same server into the single row they become.
  ///
  /// The last of them wins the fields and the first keeps its place in the
  /// list — the rule `upsertAll` gets for free from `insertAllOnConflictUpdate`
  /// and the one `ImportLinksUseCase` applies to a paste, so a server listed
  /// twice lands where it would have landed had the two entries arrived one
  /// after another.
  ///
  /// Only survivors reach `_writeSecrets`, so the credentials in the keystore
  /// belong to the row that was actually stored (R2).
  static List<ProxyNode> _foldDuplicates(List<ProxyNode> nodes) {
    final byId = <String, ProxyNode>{};
    for (final node in nodes) {
      byId[node.id] = node;
    }
    return byId.values.toList();
  }

  SimpleSelectStatement<$NodeRowsTable, NodeRow> _orderedNodes() {
    return _db.select(_db.nodeRows)
      ..orderBy(<OrderClauseGenerator<$NodeRowsTable>>[
        (table) => OrderingTerm(expression: table.sortIndex),
        (table) => OrderingTerm(expression: table.name),
      ]);
  }

  Future<List<ProxyNode>> _hydrateAll(List<NodeRow> rows) async {
    if (rows.isEmpty) {
      return const <ProxyNode>[];
    }
    // One keystore round trip for the whole list rather than one per node: on
    // Android every read crosses a platform channel and hits the Keystore.
    const noSecrets = <String, Map<String, Object?>>{};
    final secrets = await _secrets.readAllNodeParams();
    final byNodeId = secrets.valueOrNull ?? noSecrets;
    return rows
        .map(
          (row) => NodeMapper.toDomain(
            row,
            secretParams: byNodeId[row.id] ?? const <String, Object?>{},
          ),
        )
        .toList();
  }

  Future<void> _writeSecrets(ProxyNode node) async {
    _rethrowFailure(
      await _secrets.writeNodeParams(node.id, NodeMapper.secretsOf(node)),
    );
  }

  Future<void> _deleteSecrets(Iterable<String> nodeIds) async {
    _rethrowFailure(await _secrets.deleteNodeParamsAll(nodeIds));
  }

  /// Re-throws a keystore failure so the surrounding guard reports it.
  ///
  /// A node whose credentials did not make it into the keystore has not been
  /// saved, whatever the database says. Reporting success there would leave the
  /// user with a server entry that fails to connect for no visible reason —
  /// exactly the silent degradation docs/09-security-privacy.md forbids.
  static void _rethrowFailure(Result<void, CommyFailure> result) {
    final failure = result.failureOrNull;
    if (failure == null) {
      return;
    }
    if (failure is StorageFailure) {
      // Re-thrown as-is so the StorageGuard around the call rebuilds an
      // identical StorageFailure rather than a second-hand one. The cause came
      // from a platform channel and is not ours to reclassify.
      // ignore: only_throw_errors
      throw failure.cause;
    }
    throw StateError('secure storage failed: ${failure.code}');
  }

  Future<List<String>> _idsWhereSubscription(String subscriptionId) async {
    final rows = await (_db.select(_db.nodeRows)
          ..where((table) => table.subscriptionId.equals(subscriptionId)))
        .get();
    return rows.map((row) => row.id).toList();
  }

  Future<List<String>> _idsWhereGroup(String groupId) async {
    final rows = await (_db.select(_db.nodeRows)
          ..where((table) => table.groupId.equals(groupId)))
        .get();
    return rows.map((row) => row.id).toList();
  }
}
