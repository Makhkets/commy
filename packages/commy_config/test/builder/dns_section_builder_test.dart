import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

Map<String, Object?> _build(
  DnsSettings dns, {
  RoutingPolicy routing = RoutingPolicy.defaults,
  ConfigPlatform platform = ConfigPlatform.android,
  Set<String> ruleSets = const <String>{},
}) =>
    DnsSectionBuilder.build(
      dns: dns,
      routing: routing,
      platform: platform,
      availableRuleSets: ruleSets,
    );

void main() {
  group('DnsSectionBuilder.parseResolver', () {
    test('reads DNS over TLS', () {
      expect(
        DnsSectionBuilder.parseResolver('tls://1.1.1.1', tag: 'r'),
        <String, Object?>{'type': 'tls', 'tag': 'r', 'server': '1.1.1.1'},
      );
    });

    test('reads a port', () {
      expect(
        DnsSectionBuilder.parseResolver('tls://1.1.1.1:8853', tag: 'r'),
        <String, Object?>{
          'type': 'tls',
          'tag': 'r',
          'server': '1.1.1.1',
          'server_port': 8853,
        },
      );
    });

    test('reads DNS over HTTPS with its request path', () {
      expect(
        DnsSectionBuilder.parseResolver(
          'https://dns.google/dns-query',
          tag: 'r',
        ),
        <String, Object?>{
          'type': 'https',
          'tag': 'r',
          'server': 'dns.google',
          'path': '/dns-query',
        },
      );
    });

    test('treats a bare address as plain udp', () {
      expect(
        DnsSectionBuilder.parseResolver('8.8.8.8', tag: 'r'),
        <String, Object?>{'type': 'udp', 'tag': 'r', 'server': '8.8.8.8'},
      );
    });

    test('reads an IPv6 literal', () {
      expect(
        DnsSectionBuilder.parseResolver(
          'udp://[2001:4860:4860::8888]:53',
          tag: 'r',
        ),
        <String, Object?>{
          'type': 'udp',
          'tag': 'r',
          'server': '2001:4860:4860::8888',
          'server_port': 53,
        },
      );
    });

    test('local means the platform resolver', () {
      expect(
        DnsSectionBuilder.parseResolver('local', tag: 'r'),
        <String, Object?>{'type': 'local', 'tag': 'r'},
      );
    });

    test('carries a detour when one is asked for', () {
      final server = DnsSectionBuilder.parseResolver(
        'tls://1.1.1.1',
        tag: 'r',
        detour: 'proxy',
      );

      expect(server['detour'], 'proxy');
    });

    test('refuses a scheme the core cannot speak', () {
      expect(
        () => DnsSectionBuilder.parseResolver('dhcp://auto', tag: 'r'),
        throwsA(isA<ConfigBuildException>()),
      );
    });
  });

  group('DnsSectionBuilder.build', () {
    test('always defines a remote and a direct resolver', () {
      final section = _build(DnsSettings.defaults);
      final servers = section['servers']! as List<Object?>;
      final remote = servers.first! as Map<String, Object?>;
      final direct = servers[1]! as Map<String, Object?>;

      expect(remote['tag'], 'dns-remote');
      expect(remote['detour'], 'proxy');
      expect(direct['tag'], 'dns-direct');
      expect(direct.containsKey('detour'), isFalse);
      expect(section['final'], 'dns-remote');
    });

    test('adds the FakeIP resolver and its rule only when asked', () {
      final off = _build(DnsSettings.defaults);
      final on = _build(const DnsSettings(fakeIp: true));
      final servers = on['servers']! as List<Object?>;
      final rules = on['rules']! as List<Object?>;

      expect(off['servers']! as List<Object?>, hasLength(2));
      expect(servers, hasLength(3));
      expect((servers.last! as Map<String, Object?>)['type'], 'fakeip');
      expect(rules.last, <String, Object?>{
        'query_type': <String>['A', 'AAAA'],
        'server': 'dns-fake',
      });
    });

    test('forces an independent cache when FakeIP is on', () {
      final section = _build(
        const DnsSettings(fakeIp: true, independentCache: false),
      );

      expect(section['independent_cache'], isTrue);
    });

    test('sends a directly routed name to the direct resolver', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'domain_suffix:bank.example',
              action: RuleAction.direct,
            ),
          ],
        ),
      );
      final rules = section['rules']! as List<Object?>;

      expect(rules.single, <String, Object?>{
        'domain_suffix': <String>['bank.example'],
        'server': 'dns-direct',
      });
    });

    test('refuses to answer for a blocked name', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'domain_keyword:ads',
              action: RuleAction.block,
            ),
          ],
        ),
      );
      final rules = section['rules']! as List<Object?>;

      expect(
        (rules.single! as Map<String, Object?>)['action'],
        'reject',
      );
    });

    test('ignores an address matcher, which a query cannot match', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'geoip:private',
              action: RuleAction.direct,
            ),
          ],
        ),
      );

      expect(section.containsKey('rules'), isFalse);
    });

    test('ignores the rule list outside rules mode', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          mode: RoutingMode.global,
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'domain_suffix:bank.example',
              action: RuleAction.direct,
            ),
          ],
        ),
      );

      expect(section.containsKey('rules'), isFalse);
    });

    test('drops a rule whose rule set is not on disk', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'geosite:ru',
              action: RuleAction.direct,
            ),
          ],
        ),
      );

      expect(section.containsKey('rules'), isFalse);
    });

    test('keeps a rule whose rule set is on disk', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(
          rules: <RoutingRule>[
            RoutingRule(
              id: 'r1',
              matcher: 'geosite:ru',
              action: RuleAction.direct,
            ),
          ],
        ),
        ruleSets: const <String>{'geosite-ru'},
      );
      final rules = section['rules']! as List<Object?>;

      expect(rules.single, <String, Object?>{
        'rule_set': <String>['geosite-ru'],
        'server': 'dns-direct',
      });
    });
  });
}
