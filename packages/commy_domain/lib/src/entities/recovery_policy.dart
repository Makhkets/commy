import 'package:commy_domain/src/entities/recovery_manifest.dart';
import 'package:commy_domain/src/entities/subscription_recovery.dart';

/// What a manifest did to a subscription's recovery state.
enum RecoveryVerdict {
  /// The first valid manifest: its key is now pinned.
  pinned,

  /// A newer release, taken silently.
  adopted,

  /// The release already accepted, said again.
  unchanged,

  /// An older release than the one accepted: a replay, ignored.
  stale,

  /// A release the user already turned down, or an older one.
  declined,

  /// A change the user has to answer: a new main address, or new hosts from
  /// somewhere other than the main address.
  pending,

  /// Not taken: a manifest from a mirror or a meeting point for a
  /// subscription that has no pinned key. Those are only ever asked when
  /// there is one, so this is something answering that should not.
  refused,
}

/// The state after a manifest was considered, and what happened.
class RecoveryUpdate {
  /// Creates the update.
  const RecoveryUpdate(this.state, this.verdict);

  /// The recovery state to store; `null` only when there was none and the
  /// manifest was [RecoveryVerdict.refused].
  final SubscriptionRecovery? state;

  /// What happened.
  final RecoveryVerdict verdict;

  @override
  String toString() => 'RecoveryUpdate(${verdict.name})';
}

/// The trust rules of docs/adr/0019-subscription-domain-recovery.md, as one
/// pure function.
///
/// Nothing here checks a signature or touches the network: [consider] is
/// handed a manifest whose signature already held against the pinned key
/// (`ManifestReader`), and decides what that manifest may change.
abstract final class RecoveryPolicy {
  /// How often a meeting point is asked while everything works: the way to
  /// learn of a move when the old domain was taken over rather than blocked
  /// and still answers — with someone else's content.
  static const Duration rendezvousEvery = Duration(hours: 24);

  /// How often a meeting point is asked while the subscription's addresses
  /// all fail. The same pause the refresh scheduler gives a failing panel.
  static const Duration rendezvousBackoff = Duration(minutes: 15);

  /// What [manifest], verified, does to [state], for the subscription at
  /// [subscriptionUrl], given it arrived from [source].
  static RecoveryUpdate consider({
    required SubscriptionRecovery? state,
    required RecoveryManifest manifest,
    required RecoverySource source,
    required Uri subscriptionUrl,
  }) {
    final current = SignedManifest.originOf(subscriptionUrl);
    final originChanged = current == null || manifest.origin != current;

    if (state == null) {
      if (source != RecoverySource.primary) {
        return const RecoveryUpdate(null, RecoveryVerdict.refused);
      }
      final pinned = SubscriptionRecovery.pinned(manifest);
      if (!originChanged) {
        return RecoveryUpdate(pinned, RecoveryVerdict.pinned);
      }
      // The subscription's own address answered with a manifest that names
      // another one as main: the provider moved and the user subscribed
      // through the old address. The key is pinned — it came from the address
      // the user chose — but the move itself is a question, and nothing of
      // the release is taken until it is answered.
      return RecoveryUpdate(
        SubscriptionRecovery(
          id: manifest.id,
          key: manifest.key,
          nextKey: manifest.nextKey,
          seq: 0,
          rendezvous: manifest.rendezvous,
          name: manifest.name,
          pending: PendingDomainChange(manifest: manifest, source: source),
        ),
        RecoveryVerdict.pending,
      );
    }

    if (manifest.seq < state.seq) {
      return RecoveryUpdate(state, RecoveryVerdict.stale);
    }
    if (manifest.seq == state.seq) {
      return RecoveryUpdate(state, RecoveryVerdict.unchanged);
    }
    if (manifest.seq <= state.declinedSeq) {
      return RecoveryUpdate(state, RecoveryVerdict.declined);
    }
    final waiting = state.pending;
    if (waiting != null && manifest.seq <= waiting.manifest.seq) {
      return RecoveryUpdate(state, RecoveryVerdict.pending);
    }

    final newHosts = manifest.mirrors.any(
      (mirror) => !state.mirrors.contains(mirror),
    );
    final silent =
        !originChanged && (source == RecoverySource.primary || !newHosts);
    if (silent) {
      return RecoveryUpdate(state.adopt(manifest), RecoveryVerdict.adopted);
    }
    return RecoveryUpdate(
      state.copyWith(
        pending: PendingDomainChange(manifest: manifest, source: source),
      ),
      RecoveryVerdict.pending,
    );
  }

  /// The state after the user accepted the pending change, and the
  /// subscription's address under it: [url] with the scheme, host and port of
  /// the new main address, path and query — the token — kept.
  ///
  /// `null` when nothing is pending.
  static ({SubscriptionRecovery state, Uri url})? accept(
    SubscriptionRecovery state,
    Uri url,
  ) {
    final waiting = state.pending;
    if (waiting == null) {
      return null;
    }
    return (
      state: state.adopt(waiting.manifest).copyWith(pending: null),
      url: swapOrigin(url, waiting.manifest.origin),
    );
  }

  /// The state after the user turned the pending change down.
  ///
  /// The release is remembered and not offered again; a later one is.
  static SubscriptionRecovery decline(SubscriptionRecovery state) {
    final waiting = state.pending;
    if (waiting == null) {
      return state;
    }
    return state.copyWith(
      pending: null,
      declinedSeq: waiting.manifest.seq > state.declinedSeq
          ? waiting.manifest.seq
          : state.declinedSeq,
    );
  }

  /// [url] moved to [origin]: scheme, host and port from [origin], the rest
  /// from [url]. The fragment is dropped — the panel never sees one.
  static Uri swapOrigin(Uri url, Uri origin) => Uri(
        scheme: origin.scheme,
        userInfo: url.userInfo.isEmpty ? null : url.userInfo,
        host: origin.host,
        port: origin.hasPort ? origin.port : null,
        path: url.path,
        query: url.hasQuery ? url.query : null,
      );

  /// Whether a meeting point should be asked at [now].
  ///
  /// [primaryFailed] is true when neither the main address nor a mirror
  /// answered with a subscription; then the pause is [rendezvousBackoff],
  /// otherwise [rendezvousEvery].
  static bool rendezvousDue(
    SubscriptionRecovery state,
    DateTime now, {
    required bool primaryFailed,
  }) {
    if (!state.enabled || state.rendezvous.isEmpty) {
      return false;
    }
    final last = state.lastRendezvousAt;
    if (last == null) {
      return true;
    }
    final pause = primaryFailed ? rendezvousBackoff : rendezvousEvery;
    return !now.isBefore(last.add(pause));
  }
}
