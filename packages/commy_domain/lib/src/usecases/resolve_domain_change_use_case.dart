import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/recovery_policy.dart';
import 'package:commy_domain/src/entities/subscription.dart';
import 'package:commy_domain/src/entities/subscription_identity.dart';
import 'package:commy_domain/src/ports/subscription_repository.dart';

/// The user's answer to a provider's signed change of address
/// (docs/adr/0019-subscription-domain-recovery.md).
///
/// Accepting moves the subscription — scheme, host and port; the token in
/// the path stays — and takes the release whole: its mirrors, its meeting
/// points, a rotated key. Declining keeps everything as it was and remembers
/// the release, so it is not offered again. Either way the card, its
/// servers and the user's selection stay where they are: it is the same
/// subscription (ADR-0008).
class ResolveDomainChangeUseCase {
  /// Creates the use case.
  const ResolveDomainChangeUseCase({required this.subscriptions});

  /// Where the subscription lives.
  final SubscriptionRepository subscriptions;

  /// Answers the change pending on [subscriptionId]; returns the stored
  /// subscription. Nothing pending is not an error: the answer was already
  /// given, from another screen or a second tap.
  Future<Result<Subscription, CommyFailure>> call({
    required String subscriptionId,
    required bool accept,
  }) async {
    try {
      final found = await subscriptions.findById(subscriptionId);
      final failure = found.failureOrNull;
      if (failure != null) {
        return Err<Subscription, CommyFailure>(failure);
      }
      final subscription = found.valueOrNull;
      if (subscription == null) {
        return const Err<Subscription, CommyFailure>(
          SubscriptionMalformedFailure('No such subscription'),
        );
      }
      final state = subscription.recovery;
      if (state == null || state.pending == null) {
        return Ok<Subscription, CommyFailure>(subscription);
      }
      // A URL that is only its redacted form came from a keystore that
      // could not be read: moving it would write `/redacted` for good.
      if (accept && SubscriptionIdentity.isUnknown(subscription.url)) {
        return const Err<Subscription, CommyFailure>(
          StorageFailure('The subscription address could not be read'),
        );
      }
      final Subscription answered;
      if (accept) {
        final moved = RecoveryPolicy.accept(state, subscription.url)!;
        answered = subscription.copyWith(url: moved.url, recovery: moved.state);
      } else {
        answered = subscription.copyWith(
          recovery: RecoveryPolicy.decline(state),
        );
      }
      final stored = await subscriptions.upsert(answered);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err<Subscription, CommyFailure>(storeFailure);
      }
      return Ok<Subscription, CommyFailure>(answered);
    } on Object catch (error, stackTrace) {
      return Err<Subscription, CommyFailure>(
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }
}
