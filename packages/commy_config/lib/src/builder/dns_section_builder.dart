import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/route_matcher.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `dns` section.
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

  /// Turns a resolver string such as `tls://1.1.1.1` into a server object.
  ///
  /// `local` means the platform resolver. A bare address means plain UDP,
  /// which is what every panel and every user means by `8.8.8.8`.
  static Map<String, Object?> parseResolver(
    String raw, {
    required String tag,
    String? detour,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'local') {
      return <String, Object?>{
        SingBoxKeys.type: 'local',
        SingBoxKeys.tag: tag,
        if (detour != null) SingBoxKeys.detour: detour,
      };
    }

    final separator = trimmed.indexOf('://');
    final scheme = separator <= 0
        ? 'udp'
        : schemes[trimmed.substring(0, separator).toLowerCase()];
    if (scheme == null) {
      throw ConfigBuildException(
        'Resolver "${trimmed.substring(0, separator)}://" is not one the core '
        'can speak',
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
      throw ConfigBuildException('Resolver "$raw" carries no address');
    }

    return <String, Object?>{
      SingBoxKeys.type: scheme,
      SingBoxKeys.tag: tag,
      SingBoxKeys.server: address.key,
      if (address.value != null) SingBoxKeys.serverPort: address.value,
      if ((scheme == 'https' || scheme == 'h3') && path.isNotEmpty)
        SingBoxKeys.dnsPath: path,
      if (detour != null) SingBoxKeys.detour: detour,
    };
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
