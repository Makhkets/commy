import 'package:commy_domain/commy_domain.dart';

/// Signature of the scrubber `AppLogger` runs every message through.
///
/// A function rather than a class so the composition root can hand the logger
/// the richer redactor that lives in `commy_data` (`LogRedactor.redact`, which
/// also knows the addresses of the user's own servers) without `commy_core`
/// depending on `commy_data` — that edge does not exist and must not appear.
typedef LogRedaction = String Function(String message);

/// The scrubber `AppLogger` uses when nobody supplied a better one.
///
/// Rule R3 says credentials never reach a log the user can copy. This is the
/// floor, not the ceiling: it is deliberately thin and delegates the hard part
/// — deciding which parts of a URL are a secret — to [Redact] in `commy_domain`
/// rather than growing a second copy of that logic here. `commy_data` layers a
/// wider net on top for the log screen and for exports; this one guards the
/// lines the app writes about itself, which are the ones nobody thinks about.
///
/// What it removes:
///
/// * every URL-shaped token, through [Redact.link] — that covers a `vless://`
///   link (credentials in the userinfo, parameters in the query) and a
///   subscription URL (access token in the path or the query) in one call;
/// * bare canonical UUIDs, which are the whole credential for VLESS and VMess;
/// * the value of a credential-shaped `key=value` or `key: value` pair.
///
/// What it keeps, on purpose: level, time, component, error text, host names
/// and the fragment of a proxy link, which holds the node's display name. Strip
/// those and the log stops being worth reading, which is the only reason it
/// exists.
abstract final class DefaultLogRedaction {
  /// Matches a canonical UUID anywhere in the text.
  static final RegExp uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );

  /// Matches any `scheme://…` run up to the next separator.
  static final RegExp urlPattern = RegExp(
    r'[a-zA-Z][a-zA-Z0-9+.\-]{1,31}://[^\s"' "'" r'<>\\]+',
  );

  /// Matches `key=value`, `key: value` and `"key": "value"`.
  ///
  /// The optional quote after the key is what makes it work on the JSON
  /// fragments core logs are full of.
  static final RegExp credentialPattern = RegExp(
    r'\b(uuid|password|passwd|pwd|psk|pre[_-]?shared[_-]?key|'
    'private[_-]?key|public[_-]?key|short[_-]?id|obfs[_-]?password|'
    'auth[_-]?str|token|secret|api[_-]?key)'
    r'''["']?\s*[=:]\s*(?:"([^"]*)"|'([^']*)'|([^\s,;&}\)\]"']+))''',
    caseSensitive: false,
  );

  /// Matches a credential-bearing HTTP header and everything after the colon.
  ///
  /// Separate from [credentialPattern] because a header value is not one token:
  /// `Authorization: Bearer <token>` would otherwise lose the word `Bearer` and
  /// keep the part that matters.
  static final RegExp headerPattern = RegExp(
    r'\b(authorization|proxy-authorization|x-api-key|api-key|cookie|'
    r'set-cookie)\s*:\s*[^\r\n]+',
    caseSensitive: false,
  );

  /// Trailing characters that belong to the sentence, not to the URL.
  static const String urlTrailers = '.,;:!?)]}>';

  /// Returns [message] with every secret replaced.
  static String apply(String message) {
    if (message.isEmpty) {
      return message;
    }
    var result = message.replaceAllMapped(
      headerPattern,
      (match) => '${match.group(1)}: ${Redact.placeholder}',
    );
    result = result.replaceAllMapped(urlPattern, _redactUrl);
    result = result.replaceAllMapped(
      credentialPattern,
      (match) => '${match.group(1)}=${Redact.placeholder}',
    );
    return result.replaceAll(uuidPattern, Redact.placeholder);
  }

  static String _redactUrl(Match match) {
    final matched = match.group(0)!;
    var end = matched.length;
    while (end > 0 && urlTrailers.contains(matched[end - 1])) {
      end--;
    }
    final url = matched.substring(0, end);
    final trailer = matched.substring(end);
    return '${Redact.link(url)}$trailer';
  }
}
