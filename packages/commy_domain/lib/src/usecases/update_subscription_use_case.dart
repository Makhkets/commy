import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
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
/// never leave the user with half a list. Quota, title and interval are
/// refreshed only where the panel actually reported them.
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

      final refreshed = payload.applyTo(
        existing.copyWith(lastUpdatedAt: DateTime.now()),
      );
      final stored = await subscriptions.upsert(refreshed);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(storeFailure);
      }

      final owned = <ProxyNode>[
        for (final node in outcome.nodes)
          node.copyWith(subscriptionId: subscriptionId),
      ];
      final replaced = await nodes.replaceForSubscription(
        subscriptionId: subscriptionId,
        nodes: owned,
      );
      final replaceFailure = replaced.failureOrNull;
      if (replaceFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(replaceFailure);
      }

      return Ok<SubscriptionSyncResult, CommyFailure>(
        SubscriptionSyncResult(
          subscription: refreshed,
          outcome: outcome.copyWith(nodes: owned),
        ),
      );
    } on Object catch (error, stackTrace) {
      return Err<SubscriptionSyncResult, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }
}
