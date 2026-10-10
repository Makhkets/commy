import 'package:commy_domain/src/entities/recovery_manifest.dart';
import 'package:commy_domain/src/entities/recovery_policy.dart';
import 'package:commy_domain/src/entities/subscription_recovery.dart';
import 'package:commy_domain/src/ports/rendezvous_fetcher.dart';
import 'package:commy_domain/src/usecases/manifest_reader.dart';

/// The recovery half of adding and refreshing a subscription
/// (docs/adr/0019-subscription-domain-recovery.md).
///
/// Shared by both use cases so that a manifest is treated the same whether
/// it arrived with the first download or the hundredth. Holds no state of its
/// own: everything it learns goes back into the [SubscriptionRecovery] the
/// caller stores with the subscription.
class RecoveryEngine {
  /// Creates the engine.
  const RecoveryEngine({
    required this.reader,
    this.rendezvous,
    this.clock = DateTime.now,
  });

  /// What checks a manifest before it is believed.
  final ManifestReader reader;

  /// What asks the provider's meeting points, exception E-4. Without one the
  /// manifests in answers are still read — that costs no request — but no
  /// meeting point is ever asked.
  final RendezvousFetcher? rendezvous;

  /// The time, for the meeting points' schedule.
  final DateTime Function() clock;

  /// Applies the manifest an answer from [source] carried, if there was one
  /// and it holds.
  ///
  /// `null` when there was nothing to apply. A first pin counts as a visit:
  /// the subscription's own address has just spoken, and asking a meeting
  /// point in the same breath would only repeat it.
  Future<RecoveryUpdate?> take(
    String? compact, {
    required SubscriptionRecovery? state,
    required RecoverySource source,
    required Uri subscriptionUrl,
  }) async {
    final manifest = await reader.read(compact, pinned: state);
    if (manifest == null) {
      return null;
    }
    final update = RecoveryPolicy.consider(
      state: state,
      manifest: manifest,
      source: source,
      subscriptionUrl: subscriptionUrl,
    );
    final next = update.state;
    if (state == null && next != null) {
      return RecoveryUpdate(
        next.copyWith(lastRendezvousAt: clock()),
        update.verdict,
      );
    }
    return update;
  }

  /// Asks the meeting points of [state] for a newer manifest, when one is
  /// due ([RecoveryPolicy.rendezvousDue]).
  ///
  /// `null` when none was due. Otherwise the state with the visit stamped on
  /// it — a failed visit too, or a dead meeting point would be asked on every
  /// refresh — and whatever the first point that served a believable
  /// manifest changed.
  Future<RecoveryUpdate?> visit(
    SubscriptionRecovery state, {
    required bool primaryFailed,
    required Uri subscriptionUrl,
  }) async {
    final fetcher = rendezvous;
    final now = clock();
    if (fetcher == null ||
        !RecoveryPolicy.rendezvousDue(
          state,
          now,
          primaryFailed: primaryFailed,
        )) {
      return null;
    }
    final visited = state.copyWith(lastRendezvousAt: now);
    for (final point in state.rendezvous) {
      final answer = await fetcher.fetch(point);
      final compact = answer.valueOrNull;
      if (compact == null) {
        continue;
      }
      final update = await take(
        compact,
        state: visited,
        source: RecoverySource.rendezvous,
        subscriptionUrl: subscriptionUrl,
      );
      if (update != null) {
        return RecoveryUpdate(update.state ?? visited, update.verdict);
      }
    }
    return RecoveryUpdate(visited, RecoveryVerdict.unchanged);
  }
}
