import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/recovery_manifest.dart';
import 'package:commy_domain/src/entities/recovery_policy.dart';
import 'package:commy_domain/src/entities/subscription.dart';
import 'package:commy_domain/src/entities/subscription_identity.dart';
import 'package:commy_domain/src/entities/subscription_recovery.dart';
import 'package:commy_domain/src/entities/subscription_url_change.dart';
import 'package:commy_domain/src/ports/subscription_repository.dart';

/// Points an existing subscription at a new address, keeping the card.
///
/// Panels re-issue a link when the user resets it — Remnawave does — and the
/// only way to follow used to be deleting the card and adding the new link,
/// which lost the update interval, the User-Agent override, the collapse
/// state, the recovery state and the chosen server with it. Pasting the new
/// link through import made a second card instead.
///
/// The id, and with it every server and the selection, stays. The servers
/// are the old address's until the next refresh, which the caller runs at
/// once.
///
/// The recovery state (ADR-0019) stays only while the new address is still
/// that provider's: the same origin, one of the mirrors it signed, or the
/// address of a move it signed and the user has not answered — which this
/// change then takes, as accepting would. A link of another provider drops
/// it: the old provider's mirrors and meeting points would otherwise be
/// handed the new provider's token (rule R2, the scope of exception E-4), and
/// the new provider's own manifests could never be pinned on this card. The
/// new address pins again on first use.
///
/// A card whose stored address cannot be read (the keystore lost it) can be
/// given a new one as well — it is the way to repair it.
class ChangeSubscriptionUrlUseCase {
  /// Creates the use case.
  const ChangeSubscriptionUrlUseCase({required this.subscriptions});

  /// Where subscriptions live.
  final SubscriptionRepository subscriptions;

  /// Gives subscription [subscriptionId] the address [url].
  ///
  /// [url] must be an `http` or `https` address with a host; anything else
  /// is a [SubscriptionMalformedFailure] and nothing is written.
  Future<
      Result<({SubscriptionUrlChange change, Subscription subscription}),
          CommyFailure>> call({
    required String subscriptionId,
    required Uri url,
  }) async {
    if (!isSubscriptionAddress(url)) {
      return const Err(
        SubscriptionMalformedFailure('Not an http(s) address'),
      );
    }
    try {
      final all = await subscriptions.getAll();
      final failure = all.failureOrNull;
      if (failure != null) {
        return Err(failure);
      }
      final list = all.valueOrNull ?? const <Subscription>[];
      Subscription? current;
      for (final subscription in list) {
        if (subscription.id == subscriptionId) {
          current = subscription;
        }
      }
      if (current == null) {
        return const Err(SubscriptionMalformedFailure('No such subscription'));
      }
      if (SubscriptionIdentity.same(current.url, url)) {
        const change = SubscriptionUrlChange.unchanged;
        return Ok((change: change, subscription: current));
      }
      for (final other in list) {
        if (other.id != subscriptionId &&
            SubscriptionIdentity.same(other.url, url)) {
          const change = SubscriptionUrlChange.taken;
          return Ok((change: change, subscription: other));
        }
      }
      final sameOrigin =
          SignedManifest.originOf(current.url) == SignedManifest.originOf(url);
      final moved = current.copyWith(
        url: url,
        recovery: sameOrigin
            ? current.recovery
            : _recoveryAfter(current.recovery, url),
      );
      final stored = await subscriptions.upsert(moved);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err(storeFailure);
      }
      const change = SubscriptionUrlChange.changed;
      return Ok((change: change, subscription: moved));
    } on Object catch (error, stackTrace) {
      return Err(CommyFailure.fromCaught(error, stackTrace));
    }
  }

  /// What becomes of [state] when the card moves to [url]; `null` drops it.
  static SubscriptionRecovery? _recoveryAfter(
    SubscriptionRecovery? state,
    Uri url,
  ) {
    if (state == null) {
      return null;
    }
    final origin = SignedManifest.originOf(url);
    if (origin == null) {
      return null;
    }
    final pending = state.pending;
    if (pending != null &&
        SignedManifest.originOf(pending.manifest.origin) == origin) {
      // The user went where the provider asked them to go.
      return RecoveryPolicy.accept(state, url)?.state;
    }
    final own = <Uri?>[
      for (final mirror in state.mirrors) SignedManifest.originOf(mirror),
    ];
    if (own.contains(origin)) {
      return state;
    }
    return null;
  }

  /// Whether [url] is something a subscription can be fetched from.
  static bool isSubscriptionAddress(Uri url) {
    final scheme = url.scheme.toLowerCase();
    return url.host.isNotEmpty && (scheme == 'http' || scheme == 'https');
  }
}
