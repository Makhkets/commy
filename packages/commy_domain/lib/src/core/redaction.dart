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
  /// which is what makes an import error readable. Returns [placeholder] when
  /// the input does not look like a link at all.
  static String link(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
      return placeholder;
    }
    final credentials = parsed.userInfo.isEmpty ? '' : '$placeholder@';
    final port = parsed.hasPort ? ':${parsed.port}' : '';
    final query = parsed.hasQuery ? '?$placeholder' : '';
    final fragment = parsed.hasFragment ? '#${parsed.fragment}' : '';
    return '${parsed.scheme}://$credentials'
        '${parsed.host}$port$query$fragment';
  }

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
