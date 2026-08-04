import 'package:commy_domain/commy_domain.dart';

/// Everything one subscription response turned into.
///
/// Kept separate from `SubscriptionPayload` because a payload is what the
/// transport produced and this is what the parser made of it: the same
/// response gives one payload and one outcome, and the caller usually needs
/// both — the quota block comes from the headers, the node list from the body.
class SubscriptionParseResult {
  /// Creates a result.
  const SubscriptionParseResult({
    required this.payload,
    required this.outcome,
    this.announcement,
  });

  /// The headers, already parsed.
  final SubscriptionPayload payload;

  /// The nodes, and the reasons for whatever was skipped.
  final ParseOutcome outcome;

  /// A broadcast message the panel sent, when it sent one.
  ///
  /// Shown as-is and never acted on: it is text from a remote server, not an
  /// instruction to the app.
  final String? announcement;

  /// Everything that parsed.
  List<ProxyNode> get nodes => outcome.nodes;

  /// Everything that did not.
  List<ImportFailure> get failures => outcome.failures;

  /// Quota and expiry, when the panel reported them.
  SubscriptionUserInfo? get userInfo => payload.userInfo;

  /// Whether anything at all was imported.
  bool get hasNodes => outcome.hasNodes;

  /// Applies the reported metadata onto [subscription].
  Subscription applyTo(Subscription subscription) =>
      payload.applyTo(subscription);

  /// Never prints the body: it is a list of links with credentials in them.
  @override
  String toString() => 'SubscriptionParseResult(${outcome.nodes.length} nodes, '
      '${outcome.failures.length} failures)';
}
