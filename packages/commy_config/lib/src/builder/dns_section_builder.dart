import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/route_matcher.dart';
import 'package:commy_config/src/builder/route_section_builder.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_domain/commy_domain.dart';

/// Why a resolver string cannot be turned into a server object.
///
/// A reason rather than a sentence: the message the user reads belongs to the
/// app's translations, and a builder that made up English would be a string
/// nobody could translate (CLAUDE.md §5).
enum ResolverProblem {
  /// The `scheme://` prefix names a transport the core has no support for.
  unsupportedScheme,

  /// Nothing is left to connect to once the scheme has been taken off.
  missingAddress,
}

/// Builds the `dns` section.
///
/// Ad blocking lives here too, one rule ahead of everything else: the query
/// for an advertising name is refused rather than answered and then dialled
/// into a rejected connection.
///
/// Two resolvers, always. [SingBoxTags.dnsRemote] answers for names that go
/// through the tunnel and is queried **through** it; [SingBoxTags.dnsDirect]
/// answers for names that bypass it. Mixing the two is the classic leak, so
/// every change here is rule R6 territory
/// (docs/09-security-privacy.md, "Чек-лист утечек").
///
/// The resolver objects use the typed form introduced in sing-box 1.12
/// (`{"type": "tls", "server": "1.1.1.1"}`). The legacy `{"address": "..."}`
/// form still parses at v1.13.16 but is scheduled for removal in 1.14.
abstract final class DnsSectionBuilder {
  /// FakeIP IPv4 pool, as sing-box documents it.
  static const String fakeIpV4Range = '198.18.0.0/15';

  /// FakeIP IPv6 pool, as sing-box documents it.
  static const String fakeIpV6Range = 'fc00::/18';

  /// Query types FakeIP answers. Everything else falls through to a resolver.
  static const List<String> fakeIpQueryTypes = <String>['A', 'AAAA'];

  /// Resolver schemes the core has a transport for.
  ///
  /// Read off `constant/dns.go`. `dhcp` and `tailscale` are missing on purpose:
  /// neither build tag is in our set (docs/13-libbox-reference.md).
  static const Map<String, String> schemes = <String, String>{
    'udp': 'udp',
    'tcp': 'tcp',
    'tls': 'tls',
    'dot': 'tls',
    'https': 'https',
    'doh': 'https',
    'quic': 'quic',
    'doq': 'quic',
    'h3': 'h3',
    'doh3': 'h3',
  };

  /// Builds the section.
  static Map<String, Object?> build({
    required DnsSettings dns,
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required Set<String> availableRuleSets,
  }) {
    final servers = <Map<String, Object?>>[
      parseResolver(
        dns.remote,
        tag: SingBoxTags.dnsRemote,
        detour: SingBoxTags.proxyGroup,
      ),
      parseResolver(dns.direct, tag: SingBoxTags.dnsDirect),
      if (dns.fakeIp)
        <String, Object?>{
          SingBoxKeys.type: 'fakeip',
          SingBoxKeys.tag: SingBoxTags.dnsFake,
          SingBoxKeys.inet4Range: fakeIpV4Range,
          SingBoxKeys.inet6Range: fakeIpV6Range,
        },
    ];

    final rules = <Map<String, Object?>>[
      // First, so that neither the user's own rules nor FakeIP can answer an
      // advertising name before the block does. It is the same precedence the
      // route section gives ad blocking.
      ...adBlockRules(
        routing: routing,
        availableRuleSets: availableRuleSets,
      ),
      ...policyRules(
        routing: routing,
        platform: platform,
        availableRuleSets: availableRuleSets,
      ),
      if (dns.fakeIp)
        <String, Object?>{
          SingBoxKeys.queryType: fakeIpQueryTypes,
          SingBoxKeys.dnsServer: SingBoxTags.dnsFake,
        },
    ];

    return <String, Object?>{
      SingBoxKeys.servers: servers,
      if (rules.isNotEmpty) SingBoxKeys.rules: rules,
      SingBoxKeys.finalTag: SingBoxTags.dnsRemote,
      SingBoxKeys.strategy: dns.strategy.wireName,
      // FakeIP needs it, and two resolvers answering the same name differently
      // is exactly the case a shared cache gets wrong.
      SingBoxKeys.independentCache: dns.independentCache || dns.fakeIp,
    };
  }

  /// Checks [raw] the way [parseResolver] will, without building anything.
  ///
  /// Exists so a screen can refuse a typo where it was made. Without it the
  /// only thing that noticed was the next attempt to connect, which failed
  /// somewhere else with a configuration error and left the user to work out
  /// that a DNS field two screens back was the cause.
  ///
  /// Reads the same dissection [parseResolver] does, so the two cannot start
  /// disagreeing about what a resolver is.
  static ResolverProblem? checkResolver(String raw) => _dissect(raw).problem;

  /// Turns a resolver string such as `tls://1.1.1.1` into a server object.
  ///
  /// `local` means the platform resolver. A bare address means plain UDP,
  /// which is what every panel and every user means by `8.8.8.8`.
  static Map<String, Object?> parseResolver(
    String raw, {
    required String tag,
    String? detour,
  }) {
    final parsed = _dissect(raw);
    switch (parsed.problem) {
      case ResolverProblem.unsupportedScheme:
        throw ConfigBuildException(
          'Resolver "${parsed.scheme}://" is not one the core can speak',
        );
      case ResolverProblem.missingAddress:
        throw ConfigBuildException('Resolver "$raw" carries no address');
      case null:
        break;
    }

    if (parsed.isLocal) {
      return <String, Object?>{
        SingBoxKeys.type: 'local',
        SingBoxKeys.tag: tag,
        if (detour != null) SingBoxKeys.detour: detour,
      };
    }

    final scheme = parsed.scheme;
    return <String, Object?>{
      SingBoxKeys.type: scheme,
      SingBoxKeys.tag: tag,
      SingBoxKeys.server: parsed.host,
      if (parsed.port != null) SingBoxKeys.serverPort: parsed.port,
      if ((scheme == 'https' || scheme == 'h3') && parsed.path.isNotEmpty)
        SingBoxKeys.dnsPath: parsed.path,
      if (detour != null) SingBoxKeys.detour: detour,
    };
  }

  /// Takes a resolver string apart once, for both callers above.
  ///
  /// On [ResolverProblem.unsupportedScheme] the `scheme` field holds what the
  /// user actually typed rather than a transport name, so the message can
  /// quote it back at them.
  static _Resolver _dissect(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'local') {
      return const _Resolver(isLocal: true);
    }

    final separator = trimmed.indexOf('://');
    final written =
        separator <= 0 ? '' : trimmed.substring(0, separator).toLowerCase();
    final scheme = separator <= 0 ? 'udp' : schemes[written];
    if (scheme == null) {
      return _Resolver(
        problem: ResolverProblem.unsupportedScheme,
        scheme: written,
      );
    }
    final rest = separator <= 0 ? trimmed : trimmed.substring(separator + 3);

    var authority = rest;
    var path = '';
    final slash = rest.indexOf('/');
    if (slash >= 0) {
      authority = rest.substring(0, slash);
      path = rest.substring(slash);
    }

    final address = _splitAuthority(authority);
    if (address.key.isEmpty) {
      return const _Resolver(problem: ResolverProblem.missingAddress);
    }
    return _Resolver(
      scheme: scheme,
      host: address.key,
      port: address.value,
      path: path,
    );
  }

  /// The rule that refuses an advertising name outright.
  ///
  /// This is the "through DNS" half of ad blocking (docs/07-roadmap.md, M3).
  /// [RouteSectionBuilder] rejects the *connection* to such a host, which
  /// works but happens late: the name is resolved first, through the tunnel,
  /// and only the dial that follows is refused. Refusing the query costs one
  /// rule, answers instantly, and is what every other client means by a DNS
  /// blocker.
  ///
  /// `action: reject` without a `method` answers REFUSED (`dns/router.go` at
  /// v1.13.16). Both halves stay: a name already in the system cache, or an
  /// address a program dials without asking DNS at all, never reaches this
  /// rule, and the route section is what catches it.
  ///
  /// Empty while the list is not on disk. The warning for that case belongs
  /// to [RouteSectionBuilder], which is built from the same flag and the same
  /// set — saying it twice would put the same line in the log and in the
  /// banner two times over.
  static List<Map<String, Object?>> adBlockRules({
    required RoutingPolicy routing,
    required Set<String> availableRuleSets,
  }) {
    final tag = RouteSectionBuilder.adsRuleSetTag;
    if (!routing.blockAds || !availableRuleSets.contains(tag)) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        SingBoxKeys.ruleSet: <String>[tag],
        SingBoxKeys.action: SingBoxKeys.actionReject,
      },
    ];
  }

  /// DNS rules derived from the routing policy.
  ///
  /// A name the user routes directly is resolved by the direct resolver, and a
  /// name the user blocks is refused outright. Without this a "direct" rule
  /// still leaks the name to the remote resolver through the tunnel, which is
  /// the opposite of what the user asked for.
  static List<Map<String, Object?>> policyRules({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required Set<String> availableRuleSets,
  }) {
    if (routing.mode != RoutingMode.rules) {
      return const <Map<String, Object?>>[];
    }
    final rules = <Map<String, Object?>>[];
    for (final rule in routing.activeRules) {
      if (rule.action == RuleAction.proxy) {
        continue;
      }
      final matcher = RouteMatcher.tryParse(rule.matcher, platform: platform);
      if (matcher == null || matcher.isEmpty || !matcher.matchesDomains) {
        continue;
      }
      if (!matcher.ruleSets.every(availableRuleSets.contains)) {
        continue;
      }
      rules.add(<String, Object?>{
        ...matcher.fields,
        if (rule.action == RuleAction.block)
          SingBoxKeys.action: SingBoxKeys.actionReject
        else
          SingBoxKeys.dnsServer: SingBoxTags.dnsDirect,
      });
    }
    return rules;
  }

  static MapEntry<String, int?> _splitAuthority(String authority) {
    final trimmed = authority.trim();
    if (trimmed.startsWith('[')) {
      final close = trimmed.indexOf(']');
      if (close < 0) {
        return const MapEntry<String, int?>('', null);
      }
      final host = trimmed.substring(1, close);
      final rest = trimmed.substring(close + 1);
      final port =
          rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
      return MapEntry<String, int?>(host, port);
    }
    final colon = trimmed.lastIndexOf(':');
    if (colon < 0 || trimmed.substring(0, colon).contains(':')) {
      return MapEntry<String, int?>(trimmed, null);
    }
    final port = int.tryParse(trimmed.substring(colon + 1));
    if (port == null || port < 1 || port > 65535) {
      return MapEntry<String, int?>(trimmed, null);
    }
    return MapEntry<String, int?>(trimmed.substring(0, colon), port);
  }
}

/// A resolver string taken apart: what it is, or why it is nothing.
class _Resolver {
  const _Resolver({
    this.problem,
    this.isLocal = false,
    this.scheme = '',
    this.host = '',
    this.port,
    this.path = '',
  });

  final ResolverProblem? problem;
  final bool isLocal;
  final String scheme;
  final String host;
  final int? port;
  final String path;
}
