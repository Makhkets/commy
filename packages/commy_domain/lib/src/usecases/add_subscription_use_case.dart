import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/node_duplicates.dart';
import 'package:commy_domain/src/entities/panel_notice.dart';
import 'package:commy_domain/src/entities/parse_outcome.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/subscription.dart';
import 'package:commy_domain/src/entities/subscription_identity.dart';
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
///
/// The outcome it returns describes the store, not the parser: its nodes are
/// the rows the subscription left behind, so a panel that lists one server in
/// two of its groups is reported as the one server it is. `ImportLinksUseCase`
/// says the same of a paste.
///
/// ## Adding one that is already there
///
/// It updates the one that is there rather than making a second card — the
/// owner's decision of 2026-09-17, and the only one that is safe. Node ids are
/// derived from the server, so the same server fetched under a new
/// subscription id takes its row with it: the second card would fill up and
/// the first would quietly empty. What counts as "the same URL" is
/// [SubscriptionIdentity], and the rules are written out in
/// docs/adr/0008-subscription-identity.md.
///
/// A pair of duplicates created before this existed is **not** healed here.
/// Merging them means choosing which name, which interval and which id to keep
/// for a list of servers the user may have selected from, and that is a
/// decision for a screen, not for an import.
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
  /// the host is used, which is at least recognisable. On a URL the user
  /// already has, an empty [name] keeps the name they gave that card rather
  /// than reverting it to whatever the panel calls itself.
  ///
  /// [intervalHours] is the user's own choice of refresh period, and it is
  /// applied unless the panel sent one of its own in this very response. The
  /// caller used to write it afterwards, and only when the stored value was
  /// null — which meant that on a second add the switch beside it worked and
  /// it silently did not.
  Future<Result<SubscriptionSyncResult, CommyFailure>> call({
    required Uri url,
    String? name,
    bool autoUpdate = false,
    int? intervalHours,
  }) async {
    try {
      final knownResult = await _findExisting(url);
      final knownFailure = knownResult.failureOrNull;
      if (knownFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(knownFailure);
      }
      final existing = knownResult.valueOrNull;

      // A card that is already there is fetched the way its refresh is:
      // with the User-Agent its user set for it. A panel that answers by
      // client would otherwise send the default one's answer, and the
      // servers stored from it would replace the right ones.
      final fetched = await fetcher.fetch(
        url,
        throughTunnel: false,
        userAgent: existing?.userAgentOverride,
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

      // The card being re-added is asked for again after the fetch, for the
      // reason the refresh asks: the sheet can be dismissed mid-download, and
      // in those seconds the card may be deleted, collapsed or moved. The
      // upsert below writes every column and creates as happily as it
      // updates, so building on the copy read before the fetch would put a
      // deleted card back and undo the rest.
      Subscription? fresh;
      if (existing != null) {
        final reread = await subscriptions.findById(existing.id);
        final rereadFailure = reread.failureOrNull;
        if (rereadFailure != null) {
          return Err<SubscriptionSyncResult, CommyFailure>(rereadFailure);
        }
        fresh = reread.valueOrNull;
        if (fresh == null) {
          return const Err<SubscriptionSyncResult, CommyFailure>(
            SubscriptionMalformedFailure('No such subscription'),
          );
        }
      }

      final id = fresh?.id ?? ids.newId();
      final draft = fresh == null
          ? Subscription(
              id: id,
              name: _pickName(name, payload, url),
              url: url,
              autoUpdate: autoUpdate,
              lastUpdatedAt: DateTime.now(),
            )
          : fresh.copyWith(
              // The URL is rewritten to the one just typed. It matched, so it
              // is the same account either way; keeping the stored spelling
              // would leave the card pointing at whichever of the two forms
              // happened to be saved first.
              url: url,
              name: _renamed(name) ?? fresh.name,
              autoUpdate: autoUpdate,
              lastUpdatedAt: DateTime.now(),
            );
      final subscription = _withInterval(
        payload.applyTo(draft),
        chosen: intervalHours,
        declaredByPanel: payload.updateIntervalHours,
      );

      final stored = await subscriptions.upsert(subscription);
      final storeFailure = stored.failureOrNull;
      if (storeFailure != null) {
        return Err<SubscriptionSyncResult, CommyFailure>(storeFailure);
      }

      final owned = <ProxyNode>[
        for (final node in outcome.nodes) node.copyWith(subscriptionId: id),
      ];
      final storedNodes = NodeDuplicates.folded(owned);
      final replaced = await nodes.replaceForSubscription(
        subscriptionId: id,
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
          subscription: subscription,
          outcome: outcome.copyWith(nodes: servers),
          panelNotices: PanelNotice.messages(storedNodes),
          updatedExisting: existing != null,
        ),
      );
    } on Object catch (error, stackTrace) {
      return Err<SubscriptionSyncResult, CommyFailure>(
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }

  /// The stored subscription [url] belongs to, or `null` when it is new.
  ///
  /// Fails closed. A stored subscription whose URL could not be decrypted
  /// ([SubscriptionIdentity.isUnknown]) might be this one, and there is no way
  /// to find out — so rather than guess "new" and re-parent its servers onto a
  /// second card, the add stops and says the credential store could not be
  /// read. It is a rare state and an already broken one: a subscription in it
  /// cannot be refreshed either, and the user has been told so on its card.
  Future<Result<Subscription?, CommyFailure>> _findExisting(Uri url) async {
    final all = await subscriptions.getAll();
    final failure = all.failureOrNull;
    if (failure != null) {
      return Err<Subscription?, CommyFailure>(failure);
    }
    for (final subscription in all.valueOrNull ?? const <Subscription>[]) {
      if (SubscriptionIdentity.isUnknown(subscription.url)) {
        return const Err<Subscription?, CommyFailure>(
          StorageFailure(
            'A stored subscription URL could not be read, so this one cannot '
            'be told apart from it',
          ),
        );
      }
      if (SubscriptionIdentity.same(subscription.url, url)) {
        return Ok<Subscription?, CommyFailure>(subscription);
      }
    }
    return const Ok<Subscription?, CommyFailure>(null);
  }

  /// Applies the interval the user picked, where the panel left room for it.
  ///
  /// The panel wins when it sent `profile-update-interval` in this response —
  /// that is the rule docs/05-ux-flows.md scenario 3 states. What it is *not*
  /// is "the panel wins because a value is already stored": a figure left over
  /// from an earlier add is not the panel speaking now.
  Subscription _withInterval(
    Subscription subscription, {
    required int? chosen,
    required int? declaredByPanel,
  }) {
    if (chosen == null || declaredByPanel != null) {
      return subscription;
    }
    return subscription.copyWith(updateIntervalHours: chosen);
  }

  String? _renamed(String? given) {
    final trimmed = given?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
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
