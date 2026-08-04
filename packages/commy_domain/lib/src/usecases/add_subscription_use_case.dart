import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/subscription.dart';
import 'package:commy_domain/src/entities/subscription_payload.dart';
import 'package:commy_domain/src/entities/subscription_sync_result.dart';
import 'package:commy_domain/src/ports/id_generator.dart';
import 'package:commy_domain/src/ports/link_parser.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/subscription_fetcher.dart';
import 'package:commy_domain/src/ports/subscription_repository.dart';

/// Adds a subscription: fetches it, parses it and stores both halves.
///
/// The fetch goes around the tunnel. Sending it through would make the first
/// refresh after a reinstall impossible — there is nothing to route through
/// yet (docs/05-ux-flows.md, scenario 3).
class AddSubscriptionUseCase {
  /// Creates the use case.
  const AddSubscriptionUseCase({
    required this.fetcher,
    required this.parser,
    required this.subscriptions,
    required this.nodes,
    required this.ids,
  });

  /// What downloads the document.
  final SubscriptionFetcher fetcher;

  /// What turns the document into nodes.
  final LinkParser parser;

  /// Where the subscription is stored.
  final SubscriptionRepository subscriptions;

  /// Where its nodes are stored.
  final NodeRepository nodes;

  /// Where the new identifier comes from.
  final IdGenerator ids;

  /// Fetches [url] and stores it as a subscription.
  ///
  /// [name] wins over the panel's own `profile-title`; when both are absent
  /// the host is used, which is at least recognisable.
  Future<Result<SubscriptionSyncResult, CommyFailure>> call({
    required Uri url,
    String? name,
    bool autoUpdate = false,
  }) async {
    try {
      final fetched = await fetcher.fetch(url, throughTunnel: false);
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

      final id = ids.newId();
      final draft = Subscription(
        id: id,
        name: _pickName(name, payload, url),
        url: url,
        autoUpdate: autoUpdate,
        lastUpdatedAt: DateTime.now(),
      );
      final subscription = payload.applyTo(draft);

      final stored = await subscriptions.upsert(subscription);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(storeFailure);
      }

      final owned = <ProxyNode>[
        for (final node in outcome.nodes) node.copyWith(subscriptionId: id),
      ];
      final replaced = await nodes.replaceForSubscription(
        subscriptionId: id,
        nodes: owned,
      );
      final replaceFailure = replaced.failureOrNull;
      if (replaceFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(replaceFailure);
      }

      return Ok<SubscriptionSyncResult, CommyFailure>(
        SubscriptionSyncResult(
          subscription: subscription,
          outcome: outcome.copyWith(nodes: owned),
        ),
      );
    } on Object catch (error, stackTrace) {
      return Err<SubscriptionSyncResult, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }

  String _pickName(String? given, SubscriptionPayload payload, Uri url) {
    final trimmed = given?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
    final title = payload.profileTitle?.trim() ?? '';
    if (title.isNotEmpty) {
      return title;
    }
    return url.host;
  }
}
