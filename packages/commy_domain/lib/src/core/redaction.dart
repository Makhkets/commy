/// Credential scrubbing used everywhere a value can reach a log or an export.
///
/// Rule R3: redaction happens on the output layer, not the write layer. The
/// live log view inside the app may show more; anything copied, exported or
/// attached to an issue goes through here first.
abstract final class Redact {
  /// What replaces a removed secret.
  static const String placeholder = '[redacted]';

  /// What replaces the address of a user's own server on export.
  static const String serverPlaceholder = '[server]';

  /// URL-safe form of [placeholder], for use inside a path segment.
  static const String pathPlaceholder = 'redacted';

  /// Keeps only scheme, host and port of [url]; path and query are dropped.
  ///
  /// Subscription URLs carry the access token in the path or the query, so
  /// nothing past the authority may survive. The result is for display only.
  static String uri(Uri url) {
    final port = url.hasPort ? ':${url.port}' : '';
    return '${url.scheme}://${url.host}$port/$placeholder';
  }

  /// Same as [uri], but produces a [Uri] instead of a display string.
  ///
  /// Uses [pathPlaceholder] rather than [placeholder]: square brackets are
  /// only legal in the host part of a URI, so they cannot go in a path.
  static Uri uriValue(Uri url) => Uri(
        scheme: url.scheme,
        host: url.host,
        port: url.hasPort ? url.port : null,
        path: '/$pathPlaceholder',
      );

  /// Blanks the credential parts of a proxy link such as `vless://...`.
  ///
  /// The fragment is kept on purpose: it holds the display name of the node,
  /// which is what makes an import error readable. It is shown the way the
  /// user wrote it, through [_nodeName]. Returns [placeholder] when the input
  /// does not look like a link at all.
  static String link(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return placeholder;
    }
    final credentials = parsed.userInfo.isEmpty ? '' : '$placeholder@';
    final port = parsed.hasPort ? ':${parsed.port}' : '';
    final query = parsed.hasQuery ? '?$placeholder' : '';
    final fragment = parsed.hasFragment ? '#${_nodeName(parsed.fragment)}' : '';
    return '${parsed.scheme}://$credentials'
        '${parsed.host}$port$query$fragment';
  }

  /// The display name a link's fragment holds, ready to be shown.
  ///
  /// `Uri.fragment` hands the fragment back still percent-encoded, so a node
  /// called `Amsterdam 03` arrives as `Amsterdam%2003` — and printing that
  /// undoes the one reason the fragment survives redaction at all.
  ///
  /// What comes back out of the decoder is free text: whatever a panel or a
  /// user put after the `#`, which is not always a name. Two things come off
  /// it before it is shown. Control characters go, because this string lands
  /// in a one-line log record the user is about to paste into an issue and a
  /// name holding `%0A` would forge a second one. Credential-shaped text goes
  /// too: a line pasted with the name and the parameters the wrong way round
  /// puts the query where the name belongs, and the fragment being readable
  /// is not an exemption from rule R3.
  static String _nodeName(String fragment) {
    final decoded = _decodeOrKeep(fragment)
        .replaceAll(_controlPattern, ' ')
        .trim();
    return decoded
        .replaceAllMapped(
          _credentialPattern,
          (match) => '${match.group(1)}=$placeholder',
        )
        .replaceAll(_uuidPattern, placeholder);
  }

  /// Decodes [value], keeping it as it is when it cannot be decoded.
  ///
  /// The only input is a fragment that already went through `Uri`, which
  /// normalises a stray escape (`%zz` arrives as `%25zz`), so the one failure
  /// left is an escape that is not valid UTF-8 — `%FF`. A name nobody can
  /// decode is still better shown escaped than dropped.
  static String _decodeOrKeep(String value) {
    if (!value.contains('%')) {
      return value;
    }
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  /// Characters that would split one record into two, or forge a second one.
  static final RegExp _controlPattern = RegExp(
    r'[\x00-\x1f\x7f-\x9f\u2028\u2029]',
  );

  /// A canonical UUID: the whole credential of VLESS and VMess.
  static final RegExp _uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );

  /// `key=value` and `key: value` for the keys that carry a secret.
  ///
  /// The query of a link is blanked whole, so this only has to cover what can
  /// end up on the wrong side of the `#`. The keys are the ones this app
  /// actually handles; `ProxyNode.secretParamKeys` is the same decision for a
  /// node that did parse.
  static final RegExp _credentialPattern = RegExp(
    r'\b(uuid|password|passwd|pwd|psk|pre[_-]?shared[_-]?key|'
    'private[_-]?key|public[_-]?key|short[_-]?id|sid|pbk|'
    'obfs[_-]?password|auth[_-]?str|auth|token|secret|api[_-]?key)'
    r'\s*[=:]\s*[^\s&;,]+',
    caseSensitive: false,
  );

  /// Copies [source], replacing the value of every key listed in [secretKeys].
  ///
  /// Keys are matched case-insensitively, so [secretKeys] must be lowercase.
  static Map<String, Object?> params(
    Map<String, Object?> source,
    Set<String> secretKeys,
  ) {
    return <String, Object?>{
      for (final entry in source.entries)
        entry.key: secretKeys.contains(entry.key.toLowerCase())
            ? placeholder
            : entry.value,
    };
  }
}
