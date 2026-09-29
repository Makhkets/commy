// This file builds RouteMatcher values by PARSING text, and the private helpers
// that do it are parsing steps that happen to return the enclosing type — not
// constructors in spirit. Converting them all produced a longer, harder file
// with initializer-list gymnastics and no benefit, so the lint is suppressed
// here deliberately rather than obeyed into a worse design.
// ignore_for_file: prefer_constructors_over_static_methods

import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_config/src/internal/core_regex.dart';

/// One `RoutingRule.matcher` string translated into core rule fields.
///
/// The domain deliberately keeps `matcher` as text: which matchers exist is a
/// property of the core version, not of the product (see the note on
/// `RoutingRule.matcher`). This is where that text is understood.
///
/// Accepted forms, all case-insensitive:
///
/// ```text
/// domain:example.com          domain_suffix:example.com     suffix:…
/// domain_keyword:example      domain_regex:^ads\.           keyword:…
/// geosite:ru                  geoip:ru                      geoip:private
/// ip_cidr:10.0.0.0/8          port:443                      port_range:1:200
/// process_name:curl           process_path:/usr/bin/curl    package_name:com.x
/// network:udp                 protocol:quic                 rule_set:my-set
/// ```
///
/// A bare value with no prefix is guessed: something that looks like a prefix
/// becomes `ip_cidr`, something with a dot becomes `domain_suffix`, anything
/// else becomes `domain_keyword`.
///
/// A value is written only in a form the core reads. The core parses every
/// rule when it starts and refuses the whole document over one it cannot
/// (`parse rule[i]`), so a typo here would not cost the rule, it would stop
/// every server. An address, a port, a port range or an expression the core
/// would refuse is left out instead; a matcher left with nothing is dropped
/// with a warning, like any other rule that does not apply.
class RouteMatcher {
  const RouteMatcher._({
    required this.fields,
    required this.ruleSets,
    required this.matchesDomains,
  });

  /// A matcher that is nothing but its sing-box fields.
  ///
  /// A named constructor rather than a static factory: it takes one argument
  /// and returns its own type, which is exactly what a constructor is for.
  const RouteMatcher._fields(Map<String, Object?> fields)
      : this._(
          fields: fields,
          ruleSets: const <String>{},
          matchesDomains: false,
        );

  /// A matcher backed by downloadable rule sets, which must be loaded first.
  RouteMatcher._ruleSet(
    List<String> tags, {
    required bool matchesDomains,
  }) : this._(
          fields: <String, Object?>{
            if (tags.isNotEmpty) SingBoxKeys.ruleSet: tags,
          },
          ruleSets: tags.toSet(),
          matchesDomains: matchesDomains,
        );

  /// A comma-separated list under one key, empty lists omitted.
  RouteMatcher._list(
    String key,
    String value, {
    required bool matchesDomains,
  }) : this._(
          fields: _listFields(key, value),
          ruleSets: const <String>{},
          matchesDomains: matchesDomains,
        );

  /// The same as [RouteMatcher._list], for keys that select by name.
  RouteMatcher._domains(String key, String value)
      : this._list(key, value, matchesDomains: true);

  /// Value of `geoip:` that means the private ranges rather than a country.
  static const String privateGeoip = 'private';

  /// Networks the core knows.
  static const Set<String> networks = <String>{'tcp', 'udp'};

  static final RegExp _cidr = RegExp(r'^[0-9a-fA-F:.]+/\d{1,3}$');

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// An IPv4 address as Go's `netip` reads it: no octet with a leading zero.
  static final RegExp _ipv4Octets =
      RegExp(r'^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$');

  /// A prefix length as `netip.ParsePrefix` reads it: no sign, no leading
  /// zero.
  static final RegExp _prefixBits = RegExp(r'^(0|[1-9]\d{0,2})$');

  static final RegExp _portNumber = RegExp(r'^\d{1,5}$');

  /// `1000:2000`, the core's spelling, where either end may be left out, or
  /// `1000-2000`, Xray's and Clash's, where neither may: `-1` is more likely
  /// a typo than "every port up to 1".
  static final RegExp _portRangeForm =
      RegExp(r'^(?:(\d{0,5}):(\d{0,5})|(\d{1,5})-(\d{1,5}))$');

  /// The highest port there is.
  static const int _maxPort = 65535;

  /// The rule fields, ready to be merged into a route or DNS rule.
  final Map<String, Object?> fields;

  /// Rule set tags this matcher needs loaded before it can be used.
  final Set<String> ruleSets;

  /// Whether the matcher selects by name and is therefore usable as a DNS
  /// rule as well as a route rule.
  ///
  /// An address or port matcher is not: a DNS query carries a name, and
  /// matching it on the address it has not resolved to yet is meaningless.
  final bool matchesDomains;

  /// Parses [raw] for [platform], or returns `null` when it is unusable.
  ///
  /// Returns `null` — rather than throwing — for a matcher that simply does
  /// not apply here, such as `process_name` on Android. Dropping one rule is
  /// the conservative outcome: traffic then follows the final action, which
  /// for a VPN client means the proxy rather than the open network.
  static RouteMatcher? tryParse(
    String raw, {
    required ConfigPlatform platform,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final split = trimmed.indexOf(':');
    if (split <= 0) {
      return _guess(trimmed);
    }
    final key = trimmed.substring(0, split).trim().toLowerCase();
    final value = trimmed.substring(split + 1).trim();
    if (value.isEmpty) {
      return null;
    }
    switch (key) {
      case 'domain':
        return RouteMatcher._domains(SingBoxKeys.domain, value);
      case 'domain_suffix':
      case 'suffix':
        return RouteMatcher._domains(SingBoxKeys.domainSuffix, value);
      case 'domain_keyword':
      case 'keyword':
        return RouteMatcher._domains(SingBoxKeys.domainKeyword, value);
      case 'domain_regex':
      case 'regex':
        // One value, commas and all: `{1,3}` is part of an expression.
        return CoreRegex.accepts(value)
            ? RouteMatcher._(
                fields: <String, Object?>{
                  SingBoxKeys.domainRegex: <String>[value],
                },
                ruleSets: const <String>{},
                matchesDomains: true,
              )
            : null;
      case 'geosite':
        return RouteMatcher._ruleSet(
          <String>[for (final name in _split(value)) SingBoxTags.geosite(name)],
          matchesDomains: true,
        );
      case 'geoip':
        return _geoip(value);
      case 'rule_set':
      case 'ruleset':
        return RouteMatcher._ruleSet(_split(value), matchesDomains: true);
      case 'ip_cidr':
      case 'cidr':
      case 'ip':
        return _addresses(value);
      case 'port':
        return _ports(value);
      case 'port_range':
        return _portRanges(value);
      case 'process_name':
      case 'process':
        return platform.supportsProcessRules
            ? RouteMatcher._list(
                SingBoxKeys.processName,
                value,
                matchesDomains: false,
              )
            : null;
      case 'process_path':
        return platform.supportsProcessRules
            ? RouteMatcher._list(
                SingBoxKeys.processPath,
                value,
                matchesDomains: false,
              )
            : null;
      case 'package_name':
      case 'package':
      case 'app':
        return platform.supportsPackageRules
            ? RouteMatcher._list(
                SingBoxKeys.packageName,
                value,
                matchesDomains: false,
              )
            : null;
      case 'network':
        final wanted = <String>[
          for (final item in _split(value))
            if (networks.contains(item.toLowerCase())) item.toLowerCase(),
        ];
        return wanted.isEmpty
            ? null
            : RouteMatcher._fields(
                <String, Object?>{SingBoxKeys.network: wanted},
              );
      case 'protocol':
        return RouteMatcher._list(
          SingBoxKeys.protocol,
          value,
          matchesDomains: false,
        );
      default:
        return null;
    }
  }

  static RouteMatcher _guess(String value) {
    if (_cidr.hasMatch(value)) {
      return _addresses(value);
    }
    if (_ipv4.hasMatch(value)) {
      return _addresses('$value/32');
    }
    return value.contains('.')
        ? RouteMatcher._domains(SingBoxKeys.domainSuffix, value)
        : RouteMatcher._domains(SingBoxKeys.domainKeyword, value);
  }

  static RouteMatcher _geoip(String value) {
    final names = _split(value);
    final isPrivate = names.every(
      (name) => name.toLowerCase() == privateGeoip,
    );
    if (isPrivate) {
      return const RouteMatcher._fields(
        <String, Object?>{SingBoxKeys.ipIsPrivate: true},
      );
    }
    return RouteMatcher._ruleSet(
      <String>[
        for (final name in names)
          if (name.toLowerCase() != privateGeoip) SingBoxTags.geoip(name),
      ],
      matchesDomains: false,
    );
  }

  static RouteMatcher _addresses(String value) {
    final prefixes = <String>[
      for (final item in _split(value))
        if (_isAddressOrPrefix(item)) item,
    ];
    return RouteMatcher._fields(<String, Object?>{
      if (prefixes.isNotEmpty) SingBoxKeys.ipCidr: prefixes,
    });
  }

  /// Whether the core reads [item] as an `ip_cidr` entry: a prefix for
  /// `netip.ParsePrefix`, or one address for `netip.ParseAddr`.
  static bool _isAddressOrPrefix(String item) {
    final slash = item.indexOf('/');
    final address = slash < 0 ? item : item.substring(0, slash);
    final isV6 = address.contains(':');
    if (!isV6 && !_ipv4Octets.hasMatch(address)) {
      return false;
    }
    try {
      isV6 ? Uri.parseIPv6Address(address) : Uri.parseIPv4Address(address);
    } on FormatException {
      return false;
    }
    if (slash < 0) {
      return true;
    }
    final bits = item.substring(slash + 1);
    return _prefixBits.hasMatch(bits) && int.parse(bits) <= (isV6 ? 128 : 32);
  }

  static RouteMatcher _ports(String value) {
    final ports = <int>[
      for (final item in _split(value))
        if (_port(item) case final port?) port,
    ];
    return RouteMatcher._fields(<String, Object?>{
      if (ports.isNotEmpty) SingBoxKeys.port: ports,
    });
  }

  /// [text] as a port, or `null`. The core decodes ports as 16-bit numbers,
  /// so `-1` or `70000` would not cost the rule but the document.
  static int? _port(String text) {
    if (!_portNumber.hasMatch(text)) {
      return null;
    }
    final port = int.parse(text);
    return port <= _maxPort ? port : null;
  }

  static RouteMatcher _portRanges(String value) {
    final ranges = <String>[
      for (final item in _split(value))
        if (_portRange(item) case final range?) range,
    ];
    return RouteMatcher._fields(<String, Object?>{
      if (ranges.isNotEmpty) SingBoxKeys.portRange: ranges,
    });
  }

  /// [item] as the core writes a port range, `start:end`, or `null`.
  ///
  /// The core takes only a colon (`route/rule/rule_item_port_range.go`) and
  /// answers `1000-2000`, which is how Xray and Clash write the same range,
  /// with "bad port range" for the whole document. A single port is a range
  /// of one.
  static String? _portRange(String item) {
    final single = _port(item);
    if (single != null) {
      return '$single:$single';
    }
    final match = _portRangeForm.firstMatch(item);
    if (match == null) {
      return null;
    }
    final low = match[1] ?? match[3]!;
    final high = match[2] ?? match[4]!;
    final start = low.isEmpty ? 0 : _port(low);
    final end = high.isEmpty ? _maxPort : _port(high);
    // A range that ends before it starts is one the core accepts and never
    // matches: a rule that silently does nothing.
    if (start == null || end == null || start > end) {
      return null;
    }
    return '$start:$end';
  }

  static Map<String, Object?> _listFields(String key, String value) {
    final items = _split(value);
    return <String, Object?>{if (items.isNotEmpty) key: items};
  }

  static List<String> _split(String value) => <String>[
        for (final part in value.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];

  /// Whether the matcher produced anything the core can act on.
  bool get isEmpty => fields.isEmpty;

  @override
  String toString() => 'RouteMatcher(${fields.keys.join(', ')})';
}
