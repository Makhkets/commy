import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_duplicates.dart';
import 'package:commy_domain/src/entities/panel_notice.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/recovery_manifest.dart';
import 'package:commy_domain/src/entities/recovery_policy.dart';
import 'package:commy_domain/src/entities/subscription.dart';
import 'package:commy_domain/src/entities/subscription_payload.dart';
import 'package:commy_domain/src/entities/subscription_recovery.dart';
import 'package:commy_domain/src/entities/subscription_sync_result.dart';
import 'package:commy_domain/src/ports/link_parser.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/subscription_fetcher.dart';
import 'package:commy_domain/src/ports/subscription_repository.dart';
import 'package:commy_domain/src/usecases/recovery_engine.dart';

/// Refreshes an existing subscription.
///
/// Replaces its node list in one transaction, so a half-downloaded answer can
/// never leave the user with half a list. Quota and title are refreshed only
/// where the panel actually reported them; the refresh interval only while
/// the subscription has none.
///
/// The outcome it returns describes the store, not the parser: its nodes are
/// the rows the refresh left behind, so a panel that lists one server in two of
/// its groups is reported as the one server it is. `ImportLinksUseCase` says
/// the same of a paste.
///
/// ## When the address fails
///
/// A subscription whose provider signs recovery manifests
/// (docs/adr/0019-subscription-domain-recovery.md) does not give up on its
/// own address: the provider's mirrors are tried in turn, with the same
/// request, and its meeting points are asked for a newer manifest — after a
/// failure every [RecoveryPolicy.rendezvousBackoff], otherwise once every
/// [RecoveryPolicy.rendezvousEvery]. A move of the main address is never
/// taken here; it is stored as pending and the user answers it. For such a
/// subscription an answer with no servers and no notice is a failure too —
/// a parked or taken-over domain answers 200 with a page — and the servers
/// it had are kept rather than replaced by nothing.
class UpdateSubscriptionUseCase {
  /// Creates the use case.
  const UpdateSubscriptionUseCase({
    required this.fetcher,
    required this.parser,
    required this.subscriptions,
    required this.nodes,
    this.recovery,
  });

  /// What downloads the document.
  final SubscriptionFetcher fetcher;

  /// What turns the document into nodes.
  final LinkParser parser;

  /// Where the subscription lives.
  final SubscriptionRepository subscriptions;

  /// Where its nodes live.
  final NodeRepository nodes;

  /// The recovery half; without it, manifests are not read at all.
  final RecoveryEngine? recovery;

  /// Refreshes the subscription with id [subscriptionId].
  ///
  /// [throughTunnel] exists for the rare panel that only answers from inside
  /// the tunnel; the default goes around it.
  Future<Result<SubscriptionSyncResult, CommyFailure>> call({
    required String subscriptionId,
    bool throughTunnel = false,
  }) async {
    try {
      final found = await subscriptions.findById(subscriptionId);
      final findFailure = found.failureOrNull;
      if (findFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(findFailure);
      }
      final existing = found.valueOrNull;
      if (existing == null) {
        return const Err<SubscriptionSyncResult, CommyFailure>(
          SubscriptionMalformedFailure('No such subscription'),
        );
      }

      final before = existing.recovery;
      var state = before;
      var servedBy = RecoverySource.primary;
      final engine = recovery;
      final primary = await _attempt(
        existing.url,
        existing,
        throughTunnel: throughTunnel,
        strict: engine != null && (before?.canReachOut ?? false),
      );
      var answer = primary.answer;
      if (engine != null) {
        if (answer != null) {
          final taken = await engine.take(
            answer.payload.manifest,
            state: state,
            source: RecoverySource.primary,
            subscriptionUrl: existing.url,
          );
          state = taken?.state ?? state;
        } else if (state != null && state.enabled) {
          for (final mirror in state.mirrors) {
            final attempt = await _attempt(
              RecoveryPolicy.swapOrigin(existing.url, mirror),
              existing,
              throughTunnel: throughTunnel,
              strict: true,
            );
            final served = attempt.answer;
            if (served == null) {
              continue;
            }
            answer = served;
            servedBy = RecoverySource.mirror;
            final taken = await engine.take(
              served.payload.manifest,
              state: state,
              source: RecoverySource.mirror,
              subscriptionUrl: existing.url,
            );
            state = taken?.state ?? state;
            break;
          }
        }
        if (state != null) {
          final visited = await engine.visit(
            state,
            primaryFailed: answer == null,
            subscriptionUrl: existing.url,
          );
          state = visited?.state ?? state;
        }
      }

      if (answer == null) {
        // Nothing to store but what recovery learnt — a pending move, a
        // visit stamped so a dead meeting point is not asked every minute.
        if (state != before) {
          await _keepRecovery(subscriptionId, existing.url, state);
        }
        return Err<SubscriptionSyncResult, CommyFailure>(primary.failure!);
      }
      final payload = answer.payload;
      final outcome = answer.outcome;

      // Asked again after the fetch, which can take seconds: the subscription
      // may have been deleted, or the whole library replaced from a backup,
      // while the panel was answering. Writing now would bring back what the
      // user just removed — the upsert below creates as happily as it updates.
      final current =
          (await subscriptions.findById(subscriptionId)).valueOrNull;
      if (current == null || current.url != existing.url) {
        return const Err<SubscriptionSyncResult, CommyFailure>(
          SubscriptionMalformedFailure('No such subscription'),
        );
      }

      // Built on the row as it is now, not as it was before the fetch. The
      // card's menu stays open while the spinner turns, and the upsert writes
      // every column: a rename, a collapse or auto-update switched off during
      // those seconds would otherwise be quietly put back — and the last one
      // means the app goes on polling a panel the user told it to leave be.
      // The panel owns only what `applyTo` changes; the rest is the user's.
      final applied = payload.applyTo(
        current.copyWith(
          lastUpdatedAt: DateTime.now(),
          recovery: _merged(state, current.recovery),
        ),
      );
      // Except the interval, once there is one. The panel's suggestion is
      // taken when the subscription is added (ADR-0008); after that the
      // figure is whatever the menu says, and a panel sending
      // `profile-update-interval` with every answer — Remnawave and Marzban
      // do — put its own back on the first refresh after the user picked
      // another.
      final kept = current.updateIntervalHours;
      final refreshed =
          kept == null ? applied : applied.copyWith(updateIntervalHours: kept);
      final stored = await subscriptions.upsert(refreshed);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(storeFailure);
      }

      final owned = <ProxyNode>[
        for (final node in outcome.nodes)
          node.copyWith(subscriptionId: subscriptionId),
      ];
      final storedNodes = NodeDuplicates.folded(owned);
      final replaced = await nodes.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: storedNodes,
      );
      final replaceFailure = replaced.failureOrNull;
      if (replaceFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(replaceFailure);
      }

      // Stored whole, reported as servers. The notices stay in the store so
      // the subscription card can show what the panel said; they are not
      // servers, so they are not what "imported 3" counts.
      final servers = PanelNotice.servers(storedNodes);
      return Ok<SubscriptionSyncResult, CommyFailure>(
        SubscriptionSyncResult(
          subscription: refreshed,
          outcome: outcome.copyWith(nodes: servers),
          panelNotices: PanelNotice.messages(storedNodes),
          servedBy: servedBy,
        ),
      );
    } on Object catch (error, stackTrace) {
      return Err<SubscriptionSyncResult, CommyFailure>(
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }

  /// One download of [url], parsed: an answer, or the failure that stands
  /// for it.
  ///
  /// [strict] makes an answer without servers and without a panel's notice a
  /// failure, so that the next address is tried and the stored servers are
  /// not replaced by nothing. Only for a subscription with somewhere else to
  /// turn: for the rest, an empty answer is what the panel said and the
  /// behaviour stays what it always was.
  Future<_Attempt> _attempt(
    Uri url,
    Subscription subscription, {
    required bool throughTunnel,
    required bool strict,
  }) async {
    final fetched = await fetcher.fetch(
      url,
      throughTunnel: throughTunnel,
      userAgent: subscription.userAgentOverride,
    );
    final fetchFailure = fetched.failureOrNull;
    if (fetchFailure != null) {
      return _Attempt.failed(fetchFailure);
    }
    final payload = fetched.valueOrNull;
    if (payload == null) {
      return const _Attempt.failed(
        SubscriptionMalformedFailure('Empty response'),
      );
    }
    final parsed = parser.parse(payload.body);
    final parseFailure = parsed.failureOrNull;
    if (parseFailure != null) {
      return _Attempt.failed(parseFailure);
    }
    final outcome = parsed.valueOrNull ?? ParseOutcome.empty;
    if (strict &&
        !outcome.hasNodes &&
        PanelNotice.messages(outcome.nodes).isEmpty) {
      return const _Attempt.failed(
        SubscriptionMalformedFailure('The answer held no servers'),
      );
    }
    return _Attempt((payload: payload, outcome: outcome));
  }

  /// [learnt], keeping the switch the user may have flipped while the
  /// download ran: the menu stays usable under the spinner.
  static SubscriptionRecovery? _merged(
    SubscriptionRecovery? learnt,
    SubscriptionRecovery? stored,
  ) {
    if (learnt == null || stored == null) {
      return learnt ?? stored;
    }
    return learnt.copyWith(enabled: stored.enabled);
  }

  /// Stores [state] on a refresh that brought no servers, on the row as it
  /// is now.
  Future<void> _keepRecovery(
    String subscriptionId,
    Uri fetchedUrl,
    SubscriptionRecovery? state,
  ) async {
    final current = (await subscriptions.findById(subscriptionId)).valueOrNull;
    if (current == null || current.url != fetchedUrl) {
      return;
    }
    await subscriptions.upsert(
      current.copyWith(recovery: _merged(state, current.recovery)),
    );
  }
}

/// One download, parsed — or why not.
class _Attempt {
  const _Attempt(this.answer) : failure = null;

  const _Attempt.failed(CommyFailure this.failure) : answer = null;

  final ({SubscriptionPayload payload, ParseOutcome outcome})? answer;

  final CommyFailure? failure;
}
