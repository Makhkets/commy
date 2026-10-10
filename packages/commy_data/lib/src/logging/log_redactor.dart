import 'package:commy_domain/commy_domain.dart';

/// Strips credentials out of a log line before anyone else can see it.
///
/// Rule R3, and the reason it exists: core logs get pasted into Telegram and
/// attached to GitHub issues. They contain SNI, domains, IP addresses and — the
/// part that matters — whole `vless://` links, subscription URLs with the
/// access token in the path, and `password=` fragments.
///
/// Redaction happens on the *output* layer, never on the write layer
/// (docs/09-security-privacy.md, "Как реализовано"). The buffer holds the raw
/// line; the live view redacts credentials; an export redacts credentials *and*
/// the user's own server addresses.
///
/// What survives on purpose: level, timestamp, component, event type, error
/// text, destination domain and SNI. Strip those and the log stops being worth
/// exporting, which is the only reason anybody exports it.
class LogRedactor {
  /// Creates a redactor.
  ///
  /// [serverHosts] supplies the addresses of the user's own servers. It is a
  /// callback rather than a list because the node list changes while the app
  /// runs and an export must use the set that exists at export time.
  const LogRedactor({Iterable<String> Function()? serverHosts})
      : _serverHosts = serverHosts;

  /// Matches a canonical UUID anywhere in the text.
  ///
  /// The single highest-value secret in this app: it is the whole credential
  /// for VLESS and VMess.
  static final RegExp uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
  );

  /// Matches any `scheme://host/path?query` occurrence.
  static final RegExp urlPattern = RegExp(
    r'\b([a-zA-Z][a-zA-Z0-9+.\-]{1,31})://([^\s/?#]+)([^\s"' "'" ']*)',
  );

  /// Matches `key=value`, `key: value` and `"key": "value"`.
  ///
  /// The optional quote after the key name is what makes the pattern work on a
  /// JSON fragment, and core logs are full of those. The value stops at
  /// whitespace or at a character that ends a field in a query string, a JSON
  /// object or a Go struct dump.
  static final RegExp credentialPattern = RegExp(
    // Not `\b`: `access_token`, `HTTP_AUTHORIZATION`, `conn_sid` put an
    // underscore — a word character — in front of the name, and a boundary
    // there never matched.
    '(?<![A-Za-z0-9])(uuid|password|passwd|pwd|psk|pre[_-]?shared[_-]?key|'
    'private[_-]?key|peer[_-]?public[_-]?key|short[_-]?id|sid|'
    'obfs[_-]?password|auth[_-]?str|authorization|auth|token|secret|'
    'api[_-]?key|cookie|extra)'
    r'''["']?\s*[=:]\s*(?:"([^"]*)"|'([^']*)'|([^\s,;&}\)\]"']+))''',
    caseSensitive: false,
  );

  /// Matches the generic `id` field, which VMess uses for its uuid.
  ///
  /// Handled apart from [credentialPattern] because `id=` is also how every
  /// connection, rule and goroutine in a core log identifies itself. Only
  /// values long enough to be a credential are blanked — see
  /// [minimumOpaqueSecretLength].
  static final RegExp idFieldPattern = RegExp(
    r'''\bid["']?\s*[=:]\s*(?:"([^"]*)"|'([^']*)'|([^\s,;&}\)\]"']+))''',
    caseSensitive: false,
  );

  /// Matches credential-bearing HTTP headers.
  ///
  /// As a header line — `Authorization: Bearer …`, where the rest of the line
  /// is the value — and as an entry of a JSON object or a Go map, which is how
  /// an XHTTP transport's `headers` and a dumped request reach a core log:
  /// `"Authorization":"Bearer …"`, the same inside a JSON string
  /// (`\"Authorization\":\"…\"`), and `Authorization:[Bearer …]`. A quoted
  /// value ends at its own closing quote — escaped quotes inside it do not end
  /// it — and an array at its bracket, across lines when it was
  /// pretty-printed, so the rest of the object survives. Underscore
  /// spellings (`proxy_authorization`, `HTTP_AUTHORIZATION`) count too.
  static final RegExp headerPattern = RegExp(
    '(?<![A-Za-z0-9])(authorization|proxy[_-]authorization|x[_-]api[_-]key|'
    'api[_-]key|cookie|set[_-]cookie)'
    r'''(\\?["']?)\s*:\s*'''
    r'''(?:\\"((?:[^"\\]|\\[^"])*)\\"|"((?:[^"\\]|\\.)*)"|'''
    r''''((?:[^'\\]|\\.)*)'|(\[[^\]]*\])|[^\r\n]+)''',
    caseSensitive: false,
  );

  /// Matches a `Bearer` or `Basic` credential under any header name.
  ///
  /// XHTTP headers are named by whoever runs the CDN — `X-Access`,
  /// `X-Cdn-Pass` — and that is exactly where an access token goes; no list
  /// of names catches them all, but the scheme in front of the token does.
  /// The token has to look like one — eight characters at least, with a digit
  /// or a `.`, `_`, `~`, `+`, `/` or `=` in it — so "Basic configuration" in
  /// an error message stays readable.
  static final RegExp bearerPattern = RegExp(
    r'(?<![A-Za-z0-9])(Bearer|Basic)\s+'
    '(?=[A-Za-z0-9._~+/=-]{8,})'
    '([A-Za-z0-9._~+/=-]*[0-9._~+/=][A-Za-z0-9._~+/=-]*)',
    caseSensitive: false,
  );

  /// The start of an `extra` object: the JSON an XHTTP share link carries,
  /// with request headers and possibly a second server in it
  /// (`ProxyNode.secretParamKeys`). Blanked whole, braces and all.
  static final RegExp extraObjectPattern = RegExp(
    r'''(?<![A-Za-z0-9])(\\?["']?extra\\?["']?)\s*:\s*\{''',
    caseSensitive: false,
  );

  /// Shortest `id=` value still treated as a secret rather than a counter.
  ///
  /// 16 characters: below that it is a sequence number or a short tag, above it
  /// nothing in a core log is meant to be read by a human anyway.
  static const int minimumOpaqueSecretLength = 16;

  final Iterable<String> Function()? _serverHosts;

  /// Redacts [message] for display inside the app.
  ///
  /// Credentials go; server addresses stay, because the live view is where the
  /// user diagnoses their own connection and `[server]` would make that
  /// impossible.
  String redact(String message) {
    if (message.isEmpty) {
      return message;
    }
    var result = _blankExtraObjects(message);
    result = result.replaceAllMapped(headerPattern, (match) {
      final String value;
      if (match.group(6) != null) {
        value = '[${Redact.placeholder}]';
      } else {
        final quote = match.group(3) != null
            ? r'\"'
            : match.group(4) != null
                ? '"'
                : match.group(5) != null
                    ? "'"
                    : '';
        value = '$quote${Redact.placeholder}$quote';
      }
      return '${match.group(1)}${match.group(2)}: $value';
    });
    // After the headers: a token they already blanked is gone, and the
    // `]` of a placeholder can no longer end a header array early.
    result = result.replaceAllMapped(bearerPattern, (match) {
      return '${match.group(1)} ${Redact.placeholder}';
    });
    result = result.replaceAllMapped(urlPattern, _redactUrlMatch);
    result = result.replaceAllMapped(credentialPattern, (match) {
      if (_isAlreadyRedacted(match)) {
        return match.group(0)!;
      }
      return '${match.group(1)}=${Redact.placeholder}';
    });
    result = result.replaceAllMapped(idFieldPattern, _redactIdMatch);
    return result.replaceAll(uuidPattern, Redact.placeholder);
  }

  /// Redacts [message] for an export, a copy or a bug report.
  ///
  /// Everything [redact] removes, plus the addresses of the user's own servers,
  /// which become `[server]` (docs/09-security-privacy.md, "Что вырезается
  /// всегда").
  String redactForExport(String message) =>
      _hideServers(redact(message), _serversNow());

  /// Applies [redact] or [redactForExport] to a whole line.
  LogLine redactLine(LogLine line, {required bool forExport}) => line.copyWith(
        message:
            forExport ? redactForExport(line.message) : redact(line.message),
      );

  /// Applies [redactForExport] to every one of [lines].
  ///
  /// The server list is asked for once, not once a line: an export is the
  /// whole buffer, two thousand lines, on the UI isolate, and building the
  /// same pattern two thousand times is a pause the user sees.
  List<LogLine> redactLinesForExport(Iterable<LogLine> lines) {
    final servers = _serversNow();
    return <LogLine>[
      for (final line in lines)
        line.copyWith(message: _hideServers(redact(line.message), servers)),
    ];
  }

  /// The pattern of the user's servers as they are now, or `null` for none.
  RegExp? _serversNow() {
    final hosts = _serverHosts?.call();
    return hosts == null ? null : _hostPattern(hosts);
  }

  static String _hideServers(String redacted, RegExp? servers) =>
      servers == null
          ? redacted
          : redacted.replaceAll(servers, Redact.serverPlaceholder);

  static String _redactUrlMatch(Match match) {
    final scheme = match.group(1)!;
    final authority = match.group(2)!;
    final rest = match.group(3) ?? '';

    // `user:password@host` — the whole userinfo is a credential. With no `@`
    // the authority can be the credential itself: `vmess://<base64 JSON>`
    // and the legacy `ss://<base64>` put the whole server there, uuid and
    // password included, and it walked out of the log byte for byte. The
    // rule for telling a blob from an address is `Redact`'s, so the two
    // redactors cannot drift apart on it.
    final atSign = authority.lastIndexOf('@');
    final safeAuthority = atSign >= 0
        ? '${Redact.placeholder}@${authority.substring(atSign + 1)}'
        : Redact.isOpaqueAuthority(scheme, authority)
            ? Redact.placeholder
            : authority;

    // The fragment survives: on a proxy link it is the display name of the
    // node, and "failed to parse vless://…#🇩🇪 Frankfurt" is a readable error
    // while "failed to parse vless://…" is not. It survives through
    // `Redact.link` and not as raw text, so the logs screen and the import
    // sheet answer "what is this node called" with the same string.
    final hash = rest.indexOf('#');
    final name = hash < 0 ? '' : _redactNodeName(rest.substring(hash + 1));
    // A name that redacted away to nothing leaves no lone `#` behind: it is
    // noise at the end of a line and it names no node.
    final fragment = name.isEmpty ? '' : '#$name';
    final beforeFragment = hash < 0 ? rest : rest.substring(0, hash);

    // A bare origin (`tls://1.1.1.1`, `https://panel.example.com/`) carries no
    // token and stays readable; anything with a path or a query loses it.
    final hasPayload = beforeFragment.isNotEmpty && beforeFragment != '/';
    final tail = hasPayload ? '/${Redact.placeholder}' : beforeFragment;
    return '$scheme://$safeAuthority$tail$fragment';
  }

  /// The shortest link that parses, used to reach `Redact.link` with nothing
  /// but a fragment on it.
  ///
  /// The scheme and host are ours, so they contribute no `#` of their own and
  /// the first `#` in the answer is always the separator — whatever the name
  /// turns out to contain.
  static const String _nameProbe = 'x://h';

  /// Runs a log line's fragment through the same redactor an import error uses.
  ///
  /// `Redact.link` is where the decision about a node name lives: it decodes
  /// `%20` so `Amsterdam%2003` reads as a name, drops the control characters
  /// that would forge a second log record, and blanks credential-shaped text
  /// for the link pasted with its parameters on the wrong side of the `#`. A
  /// name is attacker-controlled, so none of that may be re-derived here with
  /// a second set of rules that drift apart from the first.
  ///
  /// It takes a whole link rather than a fragment, hence [_nameProbe].
  static String _redactNodeName(String fragment) {
    final redacted = Redact.link('$_nameProbe#$fragment');
    final hash = redacted.indexOf('#');
    if (hash < 0) {
      // `Redact.link` refused the link and answered with its placeholder. That
      // cannot happen for a fragment hung on [_nameProbe], but the fallback is
      // the text as the core wrote it: escaped, and still scrubbed by the
      // credential and uuid passes that run after this one.
      return fragment;
    }
    return redacted.substring(hash + 1);
  }

  /// The placeholder, but only where a value ends right after it.
  ///
  /// The terminator lookahead is the whole point: without it
  /// `password=[redacted]hunter2` would read as already redacted and walk out
  /// of the log intact.
  static final RegExp _redactedValuePattern = RegExp(
    '${RegExp.escape(Redact.placeholder)}'
    r'''(?=$|[\s,;&}\)\]"'])''',
  );

  /// Replaces every `extra` object in [message] with the placeholder.
  ///
  /// By brace count rather than by a pattern: the object nests (`headers`,
  /// `downloadSettings`), and a regular expression cannot find where it ends.
  /// Braces inside its strings are skipped. An object cut off by the end of
  /// the line is blanked to the end.
  static String _blankExtraObjects(String message) {
    final matches = extraObjectPattern.allMatches(message).toList();
    if (matches.isEmpty) {
      return message;
    }
    final out = StringBuffer();
    var from = 0;
    for (final match in matches) {
      if (match.start < from) {
        continue;
      }
      out
        ..write(message.substring(from, match.start))
        ..write('${match.group(1)}: "${Redact.placeholder}"');
      from = _closingBrace(message, match.end - 1) + 1;
    }
    out.write(message.substring(from.clamp(0, message.length)));
    return out.toString();
  }

  /// Index of the brace closing the one at [open], or the last index of
  /// [text] when it is never closed.
  static int _closingBrace(String text, int open) {
    var depth = 0;
    var inString = false;
    for (var index = open; index < text.length; index++) {
      final char = text[index];
      if (inString) {
        if (char == r'\') {
          index++;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }
    return text.length - 1;
  }

  /// True when the value [match] found is one this redactor already blanked.
  ///
  /// `[redacted]` ends in `]`, which is one of the characters that terminate a
  /// value, so [credentialPattern] matches only `[redacted` of it and a second
  /// pass would write `password=[redacted]]`, a third `]]]`. Redaction has to
  /// be idempotent: an export redacts a buffer the live view has redacted
  /// already, and a line that grows a bracket per pass is a line the user
  /// stops believing.
  static bool _isAlreadyRedacted(Match match) {
    // A quoted value is delimited by its own quotes, so it is the placeholder
    // or it is not. Leaving it alone also keeps a JSON line parseable, which
    // rewriting it to `password=[redacted]` does not.
    final quoted = match.group(2) ?? match.group(3);
    if (quoted != null) {
      return quoted == Redact.placeholder;
    }
    // A bare value stops at `]`, so what was captured is only the head of the
    // placeholder; the tail has to be read back off the line itself.
    final value = match.group(4) ?? '';
    final start = match.end - value.length;
    if (start < 0) {
      return false;
    }
    // A header array the header pattern already blanked: `[[redacted]]`.
    return _redactedValuePattern.matchAsPrefix(match.input, start) != null ||
        match.input.startsWith('[${Redact.placeholder}]', start);
  }

  static String _redactIdMatch(Match match) {
    final value = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
    final looksOpaque = value.length >= minimumOpaqueSecretLength ||
        uuidPattern.hasMatch(value);
    return looksOpaque ? 'id=${Redact.placeholder}' : match.group(0)!;
  }

  static RegExp? _hostPattern(Iterable<String> hosts) {
    final cleaned = hosts
        .map((host) => host.trim())
        .where((host) => host.isNotEmpty)
        .toSet()
        .toList()
      // Longest first, so `example.com` cannot eat half of
      // `vpn.example.com` and leave a readable fragment behind.
      ..sort((a, b) => b.length.compareTo(a.length));
    if (cleaned.isEmpty) {
      return null;
    }
    final alternatives = cleaned.map(RegExp.escape).join('|');
    return RegExp('(?:$alternatives)', caseSensitive: false);
  }
}
