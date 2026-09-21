import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/subscription.dart';

/// What a subscription add or refresh produced.
///
/// Carries both halves the UI needs: the subscription with its fresh quota and
/// title, and the parse outcome behind the line "imported 24, skipped 3".
class SubscriptionSyncResult {
  /// Creates a result.
  const SubscriptionSyncResult({
    required this.subscription,
    required this.outcome,
    this.updatedExisting = false,
  });

  /// The stored subscription, metadata already refreshed.
  final Subscription subscription;

  /// Nodes that were imported and entries that were skipped.
  final ParseOutcome outcome;

  /// Whether this landed on a subscription the user already had.
  ///
  /// Only ever true for an add: a refresh is an update by definition and has
  /// no second case to tell apart. The import sheet reads it to say "already
  /// there — updated" instead of announcing a card that is not new, which is
  /// the difference between a silent no-op and an answer.
  final bool updatedExisting;

  /// How many nodes were imported.
  int get importedCount => outcome.nodes.length;

  /// How many entries were skipped.
  int get skippedCount => outcome.failures.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SubscriptionSyncResult &&
          other.subscription == subscription &&
          other.outcome == outcome &&
          other.updatedExisting == updatedExisting;

  @override
  int get hashCode => Object.hash(subscription, outcome, updatedExisting);

  @override
  String toString() =>
      'SubscriptionSyncResult(${subscription.id}, $importedCount imported, '
      '$skippedCount skipped)';
}
