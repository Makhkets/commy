/// A subscription handed over inside another client's import link.
///
/// A panel's subscription page carries a button for each client people
/// already use — "Add to Happ", "Import to sing-box", "Clash" — and each
/// button is a link in that client's scheme with the subscription address
/// inside it. Commy registers those schemes (the Android manifest,
/// docs/06-data-model.md) so that tapping one opens it; the link parser
/// rightly knows none of them, so the address has to be taken out here, or
/// the tap ends on "could not be read" without the panel being asked.
///
/// Only an `http` or `https` address with a host comes out. Encrypted Happ
/// links (`happ://crypt…/`) cannot be opened by anyone but Happ and are not
/// unwrapped.
abstract final class ForeignImportLink {
  /// The subscription inside [input], or `null` when it is not such a link.
  ///
  /// Understood forms:
  ///
  /// * `happ://add/<url>`
  /// * `sing-box://import-remote-profile?url=<url>#<name>`
  /// * `clash://install-config?url=<url>&name=<name>`
  /// * `sn://subscription?url=<url>&name=<name>`
  /// * `commy://import/<url>`, and the query forms above under `commy://`
  static ({Uri url, String? name})? unwrap(String input) {
    final text = input.trim();
    if (text.isEmpty || text.contains(_whitespace)) {
      return null;
    }
    final separator = text.indexOf('://');
    if (separator <= 0) {
      return null;
    }
    final scheme = text.substring(0, separator).toLowerCase();
    final rest = text.substring(separator + 3);
    switch (scheme) {
      case 'happ':
        return _pathForm(rest, host: 'add');
      case 'sing-box':
        return _queryForm(text, hosts: const <String>{'import-remote-profile'});
      case 'clash':
        return _queryForm(text, hosts: const <String>{'install-config'});
      case 'sn':
        return _queryForm(text, hosts: const <String>{'subscription'});
      case 'commy':
        return _pathForm(rest, host: 'import') ??
            _queryForm(
              text,
              hosts: const <String>{
                'import-remote-profile',
                'install-config',
                'subscription',
              },
            );
    }
    return null;
  }

  /// `<host>/<url>`, the address written out as it is.
  ///
  /// Read off the raw text rather than [Uri.path], which would fold the
  /// `//` of the inner `https://`.
  static ({Uri url, String? name})? _pathForm(
    String rest, {
    required String host,
  }) {
    final prefix = '$host/';
    if (!rest.toLowerCase().startsWith(prefix)) {
      return null;
    }
    var inner = rest.substring(prefix.length);
    if (!inner.toLowerCase().startsWith('http')) {
      return null;
    }
    if (!inner.contains('://')) {
      // Percent-encoded as a whole: https%3A%2F%2F…
      final decoded = _decode(inner);
      if (decoded == null) {
        return null;
      }
      inner = decoded;
    }
    final url = _httpUrl(inner);
    if (url == null) {
      return null;
    }
    // A fragment on the address is the name the page gave it; the panel
    // never sees a fragment anyway.
    final name = url.hasFragment ? _nameOf(url.fragment) : null;
    return (url: url.removeFragment(), name: name);
  }

  /// `<host>?url=<url>&name=<name>`, the address percent-encoded.
  static ({Uri url, String? name})? _queryForm(
    String text, {
    required Set<String> hosts,
  }) {
    final uri = Uri.tryParse(text);
    if (uri == null || !hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final String? raw;
    try {
      raw = uri.queryParameters['url'];
    } on FormatException {
      return null;
    }
    final url = raw == null ? null : _httpUrl(raw);
    if (url == null) {
      return null;
    }
    final name = _nameOf(uri.queryParameters['name'] ?? '') ??
        (uri.hasFragment ? _nameOf(uri.fragment) : null);
    return (url: url, name: name);
  }

  static Uri? _httpUrl(String raw) {
    final url = Uri.tryParse(raw.trim());
    if (url == null || url.host.isEmpty) {
      return null;
    }
    final scheme = url.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? url : null;
  }

  static String? _nameOf(String raw) {
    final name = (_decode(raw) ?? raw).trim();
    return name.isEmpty ? null : name;
  }

  /// [raw] percent-decoded, or `null` when its escapes are not valid ones.
  static String? _decode(String raw) {
    if (_brokenEscape.hasMatch(raw)) {
      return null;
    }
    try {
      return Uri.decodeComponent(raw);
    } on FormatException {
      return null;
    }
  }

  static final RegExp _brokenEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  static final RegExp _whitespace = RegExp(r'\s');
}
