import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_duplicates.dart';
import 'package:commy_domain/src/entities/panel_notice.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/subscription_sync_result.dart';
import 'package:commy_domain/src/ports/link_parser.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/subscription_fetcher.dart';
import 'package:commy_domain/src/ports/subscription_repository.dart';

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
class UpdateSubscriptionUseCase {
  /// Creates the use case.
  const UpdateSubscriptionUseCase({
    required this.fetcher,
    required this.parser,
    required this.subscriptions,
    required this.nodes,
  });

  /// What downloads the document.
  final SubscriptionFetcher fetcher;

  /// What turns the document into nodes.
  final LinkParser parser;

  /// Where the subscription lives.
  final SubscriptionRepository subscriptions;

  /// Where its nodes live.
  final NodeRepository nodes;

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

      final fetched = await fetcher.fetch(
        existing.url,
        throughTunnel: throughTunnel,
        userAgent: existing.userAgentOverride,
      );
      final fetchFailure = fetched.failureOrNull;
      if (fetchFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(fetchFailure);
      }
      final payload = fetched.valueOrNull;
      if (payload == null) {
        return const Err<SubscriptionSyncResult, CommyFailure>(
          SubscriptionMalformedFailure('Empty response'),
        );
      }

      final parsed = parser.parse(payload.body);
      final parseFailure = parsed.failureOrNull;
      if (parseFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(parseFailure);
      }
      final outcome = parsed.valueOrNull ?? ParseOutcome.empty;

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
        current.copyWith(lastUpdatedAt: DateTime.now()),
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
        ),
      );
    } on Object catch (error, stackTrace) {
      return Err<SubscriptionSyncResult, CommyFailure>(
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }
}
