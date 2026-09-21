import 'package:commy_domain/src/core/redaction.dart';

/// When two subscription URLs name the same panel account.
///
/// Adding a subscription the user already has used to produce a second card
/// with its own copy of the same servers, and the second copy quietly took the
/// first one's node rows with it — node ids are derived from the server, so
/// the same server from the same panel is the same row, and storing it under
/// the new subscription re-parented it. The owner's decision (2026-09-17) is
/// that a known URL updates the subscription it belongs to, in place.
///
/// That decision needs one thing this class exists to give: a single answer to
/// "is this the same URL", because the same account is written slightly
/// differently every time a person copies it.
///
/// ## What is ignored
///
/// * **The fragment.** It never reaches the server; `#main` is a bookmark the
///   user left on their own link.
/// * **A trailing slash.** `…/sub/` and `…/sub` are one endpoint.
/// * **The order of query parameters.** Panels and share sheets reorder them;
///   servers do not care and neither should we.
/// * **A default port**, written out or not: `https://p.example/x` and
///   `https://p.example:443/x` are the same address.
///
/// ## What is significant, and why
///
/// * **The path, including its case.** The access token lives there on most
///   panels, and tokens are case-sensitive.
/// * **The userinfo.** Two accounts on one panel are two subscriptions; that
///   is the case an index on the host would have broken.
/// * **The value of every query parameter**, for the same reason as the path.
///
/// There is deliberately no column and no index behind any of this. Rule R2
/// keeps the URL out of the plain database, so the comparison happens in
/// memory over values decrypted for the purpose; the redacted form the row
/// does carry keeps only scheme, host and port, and matching on that would
/// merge the two accounts above into one.
abstract final class SubscriptionIdentity {
  /// Ports a scheme does not need written down.
  static const Map<String, int> defaultPorts = <String, int>{
    'http': 80,
    'https': 443,
    'ws': 80,
    'wss': 443,
  };

  /// Whether [a] and [b] address the same subscription.
  ///
  /// Two URLs neither of which is a real address are **not** the same: see
  /// [isUnknown] for what that case is and why answering "yes" would be the
  /// expensive mistake.
  static bool same(Uri a, Uri b) {
    if (isUnknown(a) || isUnknown(b)) {
      return false;
    }
    return canonical(a) == canonical(b);
  }

  /// The comparable form of [url].
  ///
  /// Only ever compared with another of its own kind — it is not a display
  /// string, not a key, and not safe to log: it carries the token.
  static String canonical(Uri url) {
    final scheme = url.scheme.toLowerCase();
    final port = url.hasPort && url.port != defaultPorts[scheme]
        ? ':${url.port}'
        : '';
    final userInfo = url.userInfo.isEmpty ? '' : '${url.userInfo}@';

    var path = url.path;
    // One trailing slash, and only one: a path that is nothing but slashes is
    // the root, and the root written as `/` and as `` is the same place.
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    final query = _sortedQuery(url);
    return '$scheme://$userInfo${url.host.toLowerCase()}$port$path$query';
  }

  /// Whether [url] is the placeholder a row falls back to, not an address.
  ///
  /// `SubscriptionMapper.toDomain` hands back `Redact.uriValue(url)` when the
  /// keystore has nothing for a subscription — the app was reinstalled over
  /// its own data, or the user cleared credentials from system settings. That
  /// degradation is deliberate: a list of servers that vanishes without a word
  /// is worse than one that cannot be refreshed.
  ///
  /// It is also indistinguishable from a real URL to anything that only reads
  /// the host, which is exactly what makes it dangerous here. A caller that
  /// cannot tell whether a stored subscription is the one being added must not
  /// guess, because guessing "no" creates the duplicate this file exists to
  /// prevent and empties the card the user already had.
  static bool isUnknown(Uri url) =>
      url.path == '/${Redact.pathPlaceholder}' && !url.hasQuery;

  /// The query with its parameters in a fixed order, or an empty string.
  ///
  /// Sorted by name and then by value, so a repeated parameter keeps both of
  /// its values and two links that differ only in the order of their pairs
  /// come out identical.
  static String _sortedQuery(Uri url) {
    if (!url.hasQuery || url.query.isEmpty) {
      return '';
    }
    final pairs = url.query.split('&')..sort();
    return '?${pairs.join('&')}';
  }
}
