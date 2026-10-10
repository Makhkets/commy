import 'package:commy_config/src/internal/lenient_base64.dart';

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
/// Every form below is copied from a page that writes it, not guessed: the
/// default `app-config.json` of Remnawave's subscription page (Happ, Stash,
/// Streisand, Shadowrocket, Clash and its forks, v2rayNG, Exclave, Hiddify),
/// and the owner's own panel tooling for INCY, v2RayTun and Shadowrocket's
/// `add` wrapper (docs/06-data-model.md, "Импорт из других клиентов").
///
/// Only an `http` or `https` address with a host comes out of [unwrap].
/// Encrypted links (`happ://crypt…/`, `incy://crypt…/`) cannot be opened by
/// anyone but the client that minted them and are not unwrapped; [encryptedBy]
/// names that client so the error can say so.
abstract final class ForeignImportLink {
  /// The subscription inside [input], or `null` when it is not such a link.
  ///
  /// Understood forms:
  ///
  /// * `<scheme>://<host>/<url>` — the address written out as it is, or
  ///   percent-encoded as a whole: `happ://add/`, `incy://import/` (and
  ///   `incy://add/`), `v2raytun://import/`, `streisand://import/`,
  ///   `hiddify://import/`, and Commy's own `commy://add/` (`commy://import/`
  ///   too, for links already shared);
  /// * `<scheme>://<host>?url=<url>&name=<name>` — `sing-box://import-remote-
  ///   profile`, `clash://`, `clashmeta://`, `flclashx://`, `stash://`,
  ///   `koala-clash://`, `prizrak-box://` and `v2rayng://install-config`,
  ///   `sn://` and `exclave://subscription`, and all three under `commy://`,
  ///   with `commy://add?url=` and `commy://import?url=`;
  /// * Shadowrocket's `sub://<base64 of the url>`, its `sub://?url=<url>`
  ///   spelling, and either one wrapped in `shadowrocket://add/`.
  ///
  /// A name comes from `name=`, Shadowrocket's `remark=`, or the fragment. It
  /// is the page's name for the subscription, not the user's — see
  /// `AddSubscriptionUseCase.call`, which ranks it below the panel's own
  /// `profile-title`.
  static ({Uri url, String? name})? unwrap(String input) {
    final split = _split(input);
    if (split == null) {
      return null;
    }
    final (:scheme, :rest, :text) = split;
    for (final host in _pathForms[scheme] ?? const <String>[]) {
      final found = _pathForm(rest, host: host);
      if (found != null) {
        return found;
      }
    }
    final hosts = _queryForms[scheme];
    if (hosts != null) {
      final found = _queryForm(text, hosts: hosts);
      if (found != null) {
        return found;
      }
    }
    switch (scheme) {
      case 'sub':
        return _shadowrocket(rest);
      case 'shadowrocket':
        const wrapper = 'add/sub://';
        if (rest.toLowerCase().startsWith(wrapper)) {
          return _shadowrocket(rest.substring(wrapper.length));
        }
    }
    return null;
  }

  /// The proxy link inside [input], when another client's import link
  /// carries one instead of a subscription.
  ///
  /// v2RayTun's button takes a single server as readily as a subscription —
  /// `v2raytun://import/vless%3A%2F%2F…` is what a panel's bot sends for a
  /// lone key — and the path forms of the others are written the same way.
  /// What comes out is handed to the link parser as if it had been pasted,
  /// so a wrapped scheme the parser does not know is refused there, in the
  /// words it uses for any other unknown link.
  ///
  /// `null` for anything else, including a wrapped `http(s)` address: that is
  /// a subscription, and [unwrap] returns it.
  static String? innerLink(String input) {
    final split = _split(input);
    if (split == null) {
      return null;
    }
    for (final host in _pathForms[split.scheme] ?? const <String>[]) {
      final prefix = '$host/';
      if (!split.rest.toLowerCase().startsWith(prefix)) {
        continue;
      }
      var inner = split.rest.substring(prefix.length);
      if (!inner.contains('://')) {
        // Percent-encoded as a whole: vless%3A%2F%2F…
        inner = _decode(inner) ?? '';
      }
      final separator = inner.indexOf('://');
      if (separator <= 0) {
        return null;
      }
      final scheme = inner.substring(0, separator).toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        return null;
      }
      return inner;
    }
    return null;
  }

  /// The client that encrypted [input], when it is one of the links only
  /// that client can open: `Happ` for `happ://crypt…/`, `INCY` for
  /// `incy://crypt…/`. `null` for everything else.
  ///
  /// Panels and their bots hand these out on purpose — the address of the
  /// subscription is hidden from whoever sees the link — and the only thing
  /// Commy can do with one is say what it is, so the user asks the provider
  /// for the plain address instead of retrying a link that will never open.
  static String? encryptedBy(String input) {
    final split = _split(input);
    if (split == null || !_crypt.hasMatch(split.rest)) {
      return null;
    }
    return _encryptingClients[split.scheme];
  }

  /// Clients whose encrypted links have a recognisable shape, by scheme.
  static const Map<String, String> _encryptingClients = <String, String>{
    'happ': 'Happ',
    'incy': 'INCY',
  };

  /// Path-form hosts, by scheme: `<scheme>://<host>/<url>`.
  static const Map<String, List<String>> _pathForms = <String, List<String>>{
    'happ': <String>['add'],
    'incy': <String>['import', 'add'],
    'v2raytun': <String>['import'],
    'streisand': <String>['import'],
    'hiddify': <String>['import'],
    // `add` first: Commy's own link, in the shape every client of this kind
    // uses (`happ://add/`). `import` stays, so links already shared keep
    // opening.
    'commy': <String>['add', 'import'],
  };

  /// Query-form hosts, by scheme: `<scheme>://<host>?url=<url>`.
  static const Map<String, Set<String>> _queryForms = <String, Set<String>>{
    'sing-box': <String>{'import-remote-profile'},
    'clash': <String>{'install-config'},
    'clashmeta': <String>{'install-config'},
    'flclashx': <String>{'install-config'},
    'stash': <String>{'install-config'},
    'koala-clash': <String>{'install-config'},
    'prizrak-box': <String>{'install-config'},
    'v2rayng': <String>{'install-config'},
    'sn': <String>{'subscription'},
    'exclave': <String>{'subscription'},
    'commy': <String>{
      'add',
      'import',
      'import-remote-profile',
      'install-config',
      'subscription',
    },
  };

  /// Every scheme this class reads something out of.
  ///
  /// The Android manifest claims the same list; a test keeps the two from
  /// drifting apart.
  static Set<String> get schemes => <String>{
        ..._pathForms.keys,
        ..._queryForms.keys,
        'sub',
        'shadowrocket',
      };

  static ({String scheme, String rest, String text})? _split(String input) {
    final text = input.trim();
    if (text.isEmpty || text.contains(_whitespace)) {
      return null;
    }
    final separator = text.indexOf('://');
    if (separator <= 0) {
      return null;
    }
    return (
      scheme: text.substring(0, separator).toLowerCase(),
      rest: text.substring(separator + 3),
      text: text,
    );
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
    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } on FormatException {
      return null;
    }
    final raw = query['url'];
    final url = raw == null ? null : _httpUrl(raw);
    if (url == null) {
      return null;
    }
    final name = _nameOf(query['name'] ?? '') ??
        (uri.hasFragment ? _nameOf(uri.fragment) : null);
    return (url: url, name: name);
  }

  /// What follows Shadowrocket's `sub://`.
  ///
  /// Two spellings are in use. Remnawave's page writes the address as
  /// base64 straight after the scheme (its `isNeedBase64Encoding`), with the
  /// name, if any, in the fragment or a `remark=`; the owner's bot writes
  /// `sub://?url=<percent-encoded>&remark=<name>` and keeps the base64 one
  /// as its fallback. Either may come inside `shadowrocket://add/`.
  static ({Uri url, String? name})? _shadowrocket(String rest) {
    var body = rest;
    String? fragment;
    final hash = body.indexOf('#');
    if (hash >= 0) {
      fragment = body.substring(hash + 1);
      body = body.substring(0, hash);
    }
    var query = '';
    final question = body.indexOf('?');
    if (question >= 0) {
      query = body.substring(question + 1);
      body = body.substring(0, question);
    }
    final Map<String, String> params;
    try {
      params = query.isEmpty
          ? const <String, String>{}
          : Uri.splitQueryString(query);
    } on FormatException {
      return null;
    }
    final Uri? url;
    if (body.isEmpty) {
      final raw = params['url'];
      url = raw == null ? null : _httpUrl(raw);
    } else {
      // The base64 itself may arrive percent-encoded: `=` as `%3D`.
      final payload = body.contains('%') ? _decode(body) : body;
      final decoded = payload == null
          ? null
          : LenientBase64.decodeToString(payload, minLength: 1);
      url = decoded == null ? null : _httpUrl(decoded);
    }
    if (url == null) {
      return null;
    }
    final name = _nameOf(params['remark'] ?? '') ??
        _nameOf(params['name'] ?? '') ??
        (fragment == null ? null : _nameOf(fragment));
    return (url: url.removeFragment(), name: name);
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

  /// `crypt`, an optional version number, a slash: `crypt/`, `crypt5/`.
  static final RegExp _crypt = RegExp(r'^crypt\d*/', caseSensitive: false);
}
