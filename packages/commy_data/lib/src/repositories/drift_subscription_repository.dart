import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_data/src/mappers/subscription_mapper.dart';
import 'package:commy_data/src/secure/secret_vault.dart';
import 'package:commy_data/src/util/storage_guard.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Subscriptions, with their URLs kept in the keystore.
///
/// `Subscription.url` is the single most valuable secret in the app: it holds
/// the access token, and whoever has it has every server the user owns. It
/// never becomes a column (rule R2). What the row keeps is the *redacted* form
/// — scheme, host, port — which is precisely what `Subscription.redacted()`
/// produces and what the UI shows anyway.
///
/// Deleting a subscription also deletes its nodes: the row cascade takes the
/// rows, and this repository takes their credentials, because the keystore has
/// no foreign keys.
class DriftSubscriptionRepository implements SubscriptionRepository {
  /// Creates the repository.
  DriftSubscriptionRepository({
    required CommyDatabase database,
    required SecretVault secrets,
  })  : _db = database,
        _secrets = secrets;

  final CommyDatabase _db;
  final SecretVault _secrets;

  @override
  Stream<List<Subscription>> watchAll() {
    return _ordered().watch().asyncMap(_hydrateAll);
  }

  @override
  Future<Result<List<Subscription>, CommyFailure>> getAll() {
    return StorageGuard.run(() async => _hydrateAll(await _ordered().get()));
  }

  @override
  Future<Result<Subscription?, CommyFailure>> findById(String id) {
    return StorageGuard.run(() async {
      final row = await (_db.select(_db.subscriptionRows)
            ..where((table) => table.id.equals(id)))
          .getSingleOrNull();
      if (row == null) {
        return null;
      }
      final url = await _secrets.readSubscriptionUrl(id);
      return SubscriptionMapper.toDomain(row, url: url.valueOrNull);
    });
  }

  @override
  Future<Result<void, CommyFailure>> upsert(Subscription subscription) {
    return StorageGuard.runVoid(() async {
      // URL first. A row whose secret never landed is a subscription that
      // cannot be refreshed and gives no hint why.
      _rethrowFailure(
        await _secrets.writeSubscriptionUrl(
          subscription.id,
          subscription.url,
        ),
      );
      await _db
          .into(_db.subscriptionRows)
          .insertOnConflictUpdate(SubscriptionMapper.toCompanion(subscription));
    });
  }

  @override
  Future<Result<void, CommyFailure>> deleteById(String id) {
    return StorageGuard.runVoid(() async {
      final nodeIds = await _nodeIdsOf(id);
      _rethrowFailure(await _secrets.deleteNodeParamsAll(nodeIds));
      _rethrowFailure(await _secrets.deleteSubscriptionUrl(id));
      await (_db.delete(_db.subscriptionRows)
            ..where((table) => table.id.equals(id)))
          .go();
    });
  }

  @override
  Future<Result<void, CommyFailure>> setCollapsed({
    required String id,
    required bool isCollapsed,
  }) {
    return StorageGuard.runVoid(() async {
      await (_db.update(_db.subscriptionRows)
            ..where((table) => table.id.equals(id)))
          .write(
        SubscriptionRowsCompanion(isCollapsed: Value<bool>(isCollapsed)),
      );
    });
  }

  @override
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds) {
    return StorageGuard.runVoid(() async {
      await _db.batch((batch) {
        for (var index = 0; index < orderedIds.length; index++) {
          batch.update(
            _db.subscriptionRows,
            SubscriptionRowsCompanion(sortIndex: Value<int>(index)),
            where: (table) => table.id.equals(orderedIds[index]),
          );
        }
      });
    });
  }

  SimpleSelectStatement<$SubscriptionRowsTable, SubscriptionRow> _ordered() {
    return _db.select(_db.subscriptionRows)
      ..orderBy(<OrderClauseGenerator<$SubscriptionRowsTable>>[
        (table) => OrderingTerm(expression: table.sortIndex),
        (table) => OrderingTerm(expression: table.name),
      ]);
  }

  Future<List<Subscription>> _hydrateAll(List<SubscriptionRow> rows) async {
    if (rows.isEmpty) {
      return const <Subscription>[];
    }
    final urls = await _secrets.readAllSubscriptionUrls();
    final byId = urls.valueOrNull ?? const <String, Uri>{};
    return rows
        .map((row) => SubscriptionMapper.toDomain(row, url: byId[row.id]))
        .toList();
  }

  Future<List<String>> _nodeIdsOf(String subscriptionId) async {
    final rows = await (_db.select(_db.nodeRows)
          ..where((table) => table.subscriptionId.equals(subscriptionId)))
        .get();
    return rows.map((row) => row.id).toList();
  }

  static void _rethrowFailure(Result<void, CommyFailure> result) {
    final failure = result.failureOrNull;
    if (failure == null) {
      return;
    }
    if (failure is StorageFailure) {
      // The cause is re-thrown as-is so the StorageGuard around this call
      // rebuilds an identical StorageFailure instead of a second-hand one.
      // It came from the platform channel and is not ours to reclassify.
      // ignore: only_throw_errors
      throw failure.cause;
    }
    throw StateError('secure storage failed: ${failure.code}');
  }
}
