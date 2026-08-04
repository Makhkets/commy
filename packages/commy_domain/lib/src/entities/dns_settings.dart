import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';

/// Address family preference handed to the core resolver.
enum DnsStrategy {
  /// Ask for both, prefer A records.
  preferIpv4(wireName: 'prefer_ipv4'),

  /// Ask for both, prefer AAAA records.
  preferIpv6(wireName: 'prefer_ipv6'),

  /// A records only.
  ipv4Only(wireName: 'ipv4_only'),

  /// AAAA records only.
  ipv6Only(wireName: 'ipv6_only');

  const DnsStrategy({required this.wireName});

  /// Value the sing-box core expects.
  final String wireName;
}

/// DNS policy: which resolver answers what, and how.
///
/// Two resolvers on purpose. [remote] answers for everything that goes through
/// the tunnel and is queried through it; [direct] answers for everything that
/// bypasses the tunnel. Mixing them is the classic leak, so rule R6 applies to
/// every change here — see docs/09-security-privacy.md.
class DnsSettings {
  /// Creates a DNS policy.
  const DnsSettings({
    this.remote = defaultRemote,
    this.direct = defaultDirect,
    this.strategy = DnsStrategy.preferIpv4,
    this.fakeIp = false,
    this.independentCache = true,
  });

  /// Restores the policy from the map produced by [toJson].
  factory DnsSettings.fromJson(JsonMap json) => DnsSettings(
        remote: JsonRead.stringOr(json, 'remote', orElse: defaultRemote),
        direct: JsonRead.stringOr(json, 'direct', orElse: defaultDirect),
        strategy: DnsStrategy.values.byName(
          JsonRead.stringOr(json, 'strategy', orElse: 'preferIpv4'),
        ),
        fakeIp: JsonRead.boolean(json, 'fakeIp', orElse: false),
        independentCache: JsonRead.boolean(
          json,
          'independentCache',
          orElse: true,
        ),
      );

  /// Resolver used for names that go through the tunnel.
  static const String defaultRemote = 'tls://1.1.1.1';

  /// Resolver used for names that bypass the tunnel.
  ///
  /// `local` hands the query to the system resolver, which is the right answer
  /// for traffic that is leaving directly anyway.
  static const String defaultDirect = 'local';

  /// The default policy.
  static const DnsSettings defaults = DnsSettings();

  /// Resolver queried through the proxy.
  final String remote;

  /// Resolver queried outside the proxy.
  final String direct;

  /// Address family preference.
  final DnsStrategy strategy;

  /// Whether FakeIP is enabled.
  ///
  /// Faster and leak-proof for the sniffing path, but the real addresses must
  /// never end up in the system cache — that is on the leak checklist.
  final bool fakeIp;

  /// Whether each resolver keeps its own cache.
  final bool independentCache;

  /// Returns a copy with the given fields replaced.
  DnsSettings copyWith({
    String? remote,
    String? direct,
    DnsStrategy? strategy,
    bool? fakeIp,
    bool? independentCache,
  }) {
    return DnsSettings(
      remote: remote ?? this.remote,
      direct: direct ?? this.direct,
      strategy: strategy ?? this.strategy,
      fakeIp: fakeIp ?? this.fakeIp,
      independentCache: independentCache ?? this.independentCache,
    );
  }

  /// Serialises the policy.
  JsonMap toJson() => <String, Object?>{
        'remote': remote,
        'direct': direct,
        'strategy': strategy.name,
        'fakeIp': fakeIp,
        'independentCache': independentCache,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DnsSettings &&
          other.remote == remote &&
          other.direct == direct &&
          other.strategy == strategy &&
          other.fakeIp == fakeIp &&
          other.independentCache == independentCache;

  @override
  int get hashCode =>
      Object.hash(remote, direct, strategy, fakeIp, independentCache);

  @override
  String toString() =>
      'DnsSettings($remote, $direct, ${strategy.name}, fakeIp: $fakeIp)';
}
