import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/subscription.dart';

/// Storage of subscriptions.
///
/// Rule R2: `Subscription.url` holds an access token, so implementations keep
/// it in secure storage and only a reference to it in the database.
abstract interface class SubscriptionRepository {
  /// Every subscription, in display order, refreshed on every change.
  Stream<List<Subscription>> watchAll();

  /// Every subscription, once.
  Future<Result<List<Subscription>, CommyFailure>> getAll();

  /// One subscription, or `null` when there is no such id.
  Future<Result<Subscription?, CommyFailure>> findById(String id);

  /// Inserts or updates a subscription and its secret URL.
  Future<Result<void, CommyFailure>> upsert(Subscription subscription);

  /// Removes a subscription, its secret URL and its nodes.
  Future<Result<void, CommyFailure>> deleteById(String id);

  /// Folds or unfolds the subscription's node group in the UI.
  Future<Result<void, CommyFailure>> setCollapsed({
    required String id,
    required bool isCollapsed,
  });

  /// Rewrites the display order from the given id sequence.
  Future<Result<void, CommyFailure>> reorder(List<String> orderedIds);
}
