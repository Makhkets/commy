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

  group('DnsSectionBuilder.checkResolver', () {
    test('accepts everything the builder accepts', () {
      for (final resolver in <String>[
        'tls://1.1.1.1',
        'tls://1.1.1.1:8853',
        'https://dns.google/dns-query',
        '8.8.8.8',
        'udp://8.8.8.8:53',
        '[2606:4700:4700::1111]:53',
        'local',
        '',
        '  tls://1.1.1.1  ',
      ]) {
        expect(
          DnsSectionBuilder.checkResolver(resolver),
          isNull,
          reason: resolver,
        );
      }
    });

    test('names the scheme the core has no transport for', () {
      expect(
        DnsSectionBuilder.checkResolver('dhcp://auto'),
        ResolverProblem.unsupportedScheme,
      );
      expect(
        DnsSectionBuilder.checkResolver('tailscale://whatever'),
        ResolverProblem.unsupportedScheme,
      );
    });

    test('names a scheme with nothing behind it', () {
      expect(
        DnsSectionBuilder.checkResolver('tls://'),
        ResolverProblem.missingAddress,
      );
      expect(
        DnsSectionBuilder.checkResolver('https:///dns-query'),
        ResolverProblem.missingAddress,
      );
    });

    test('agrees with the builder on every case, by construction', () {
      // The point of the method: a screen that validates one way and a core
      // that builds another is exactly the bug this replaces.
      for (final resolver in <String>[
        'tls://1.1.1.1',
        'dhcp://auto',
        'tls://',
        'local',
      ]) {
        final rejected = DnsSectionBuilder.checkResolver(resolver) != null;
        var threw = false;
        try {
          DnsSectionBuilder.parseResolver(resolver, tag: 'r');
        } on ConfigBuildException {
          threw = true;
        }
        expect(threw, rejected, reason: resolver);
      }
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

    test('in Direct mode leaves unclaimed names to the direct resolver', () {
      // Nothing goes through the proxy in this mode. Asked through it, every
      // name failed with the server down — the moment the mode is for.
      String? finalOf(RoutingMode mode, {bool fakeIp = false}) => _build(
            DnsSettings(fakeIp: fakeIp),
            routing: RoutingPolicy(mode: mode),
          )['final'] as String?;

      expect(finalOf(RoutingMode.direct), 'dns-direct');
      expect(finalOf(RoutingMode.direct, fakeIp: true), 'dns-direct');
      expect(finalOf(RoutingMode.rules), 'dns-remote');
      expect(finalOf(RoutingMode.global), 'dns-remote');
    });

    test('in Direct mode keeps FakeIP when it is on', () {
      final section = _build(
        const DnsSettings(fakeIp: true),
        routing: const RoutingPolicy(mode: RoutingMode.direct),
      );

      expect(section['rules'], <Object?>[
        <String, Object?>{
          'query_type': <String>['A', 'AAAA'],
          'server': 'dns-fake',
        },
      ]);
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

    group('a proxied exception above a broader rule', () {
      // The route section keeps a Proxy rule where the user put it, and both
      // lists stop at the first match. Skipped here, the exception's query
      // fell through to the rule below it while its connection went through
      // the proxy.
      RoutingPolicy exception(RuleAction broader) => RoutingPolicy(
            rules: <RoutingRule>[
              const RoutingRule(
                id: 'r1',
                matcher: 'domain:example.com',
                action: RuleAction.proxy,
              ),
              RoutingRule(
                id: 'r2',
                matcher: 'domain_suffix:com',
                action: broader,
                sortIndex: 1,
              ),
            ],
          );
      const proxied = <String, Object?>{
        'domain': <String>['example.com'],
        'server': 'dns-remote',
      };

      test('is resolved through the tunnel, not by the direct resolver', () {
        final section = _build(
          DnsSettings.defaults,
          routing: exception(RuleAction.direct),
        );

        expect(section['rules'], <Object?>[
          proxied,
          <String, Object?>{
            'domain_suffix': <String>['com'],
            'server': 'dns-direct',
          },
        ]);
      });

      test('is answered, not refused by a Block rule below it', () {
        final section = _build(
          DnsSettings.defaults,
          routing: exception(RuleAction.block),
        );

        expect(section['rules'], <Object?>[
          proxied,
          <String, Object?>{
            'domain_suffix': <String>['com'],
            'action': 'reject',
          },
        ]);
      });

      test('gets a FakeIP address when FakeIP is on', () {
        final section = _build(
          const DnsSettings(fakeIp: true),
          routing: exception(RuleAction.direct),
        );

        expect(section['rules'], <Object?>[
          <String, Object?>{
            'domain': <String>['example.com'],
            'query_type': <String>['A', 'AAAA'],
            'server': 'dns-fake',
          },
          proxied,
          <String, Object?>{
            'domain_suffix': <String>['com'],
            'server': 'dns-direct',
          },
          <String, Object?>{
            'query_type': <String>['A', 'AAAA'],
            'server': 'dns-fake',
          },
        ]);
      });
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

  group('DnsSectionBuilder resolvers the core has to be told about', () {
    List<Map<String, Object?>> serversOf(DnsSettings dns) =>
        (_build(dns)['servers']! as List<Object?>).cast<Map<String, Object?>>();

    test('a direct resolver by name finds its server through the system', () {
      // Without `domain_resolver` sing-box refuses a DNS server whose address
      // is a name and that has no detour: "missing domain resolver for domain
      // server address", and the tunnel does not start.
      final servers = serversOf(
        const DnsSettings(direct: 'https://dns.google/dns-query'),
      );
      final direct = servers.firstWhere((s) => s['tag'] == 'dns-direct');

      expect(direct['server'], 'dns.google');
      expect(direct['domain_resolver'], 'dns-bootstrap');
      expect(
        servers.where((s) => s['tag'] == 'dns-bootstrap').single,
        <String, Object?>{'type': 'local', 'tag': 'dns-bootstrap'},
      );
    });

    test('a direct resolver by address, or the system one, needs nothing', () {
      for (final direct in <String>[
        'local',
        'tls://1.1.1.1',
        '[2606:4700:4700::1111]:53',
      ]) {
        final servers = serversOf(DnsSettings(direct: direct));

        expect(servers.map((s) => s['tag']), isNot(contains('dns-bootstrap')));
        expect(
          servers.firstWhere((s) => s['tag'] == 'dns-direct'),
          isNot(contains('domain_resolver')),
          reason: direct,
        );
      }
    });

    test('the resolver through the tunnel by name goes inside it', () {
      // Its detour carries the name to the server; nothing resolves it here.
      final remote = serversOf(
        const DnsSettings(remote: 'https://dns.google/dns-query'),
      ).first;

      expect(remote['detour'], 'proxy');
      expect(remote.containsKey('domain_resolver'), isFalse);
    });

    test('the system resolver is refused for the tunnel, in both places', () {
      for (final remote in <String>['local', '', ' LOCAL ']) {
        expect(
          DnsSectionBuilder.checkResolver(remote, throughTunnel: true),
          ResolverProblem.systemThroughTunnel,
          reason: remote,
        );
        expect(
          () => _build(DnsSettings(remote: remote)),
          throwsA(isA<ConfigBuildException>()),
          reason: remote,
        );
      }
      expect(DnsSectionBuilder.checkResolver('local'), isNull);
      expect(
        DnsSectionBuilder.checkResolver('tls://1.1.1.1', throughTunnel: true),
        isNull,
      );
    });

    test('the probe document gets the same bootstrap', () {
      final probe = const SingBoxConfigBuilder()
          .buildProbe(
            nodes: const <ProxyNode>[
              ProxyNode(
                id: 'n',
                name: 'n',
                protocol: Protocol.trojan,
                host: 'a.example',
                port: 443,
                params: <String, Object?>{'password': 'p', 'security': 'tls'},
              ),
            ],
            dns: const DnsSettings(direct: 'tls://dns.example'),
          )
          .valueOrNull!
          .document;
      final servers =
          ((probe['dns']! as Map<String, Object?>)['servers']! as List<Object?>)
              .cast<Map<String, Object?>>();

      expect(servers.first['domain_resolver'], 'dns-bootstrap');
      expect(servers.last['tag'], 'dns-bootstrap');
    });
  });

  group('DnsSectionBuilder ad blocking', () {
    const adsTag = 'geosite-category-ads-all';
    const policy = RoutingPolicy(blockAds: true);

    test('refuses the query when the list is on disk', () {
      final section = _build(
        DnsSettings.defaults,
        routing: policy,
        ruleSets: const <String>{adsTag},
      );
      final rules = section['rules']! as List<Object?>;

      expect(rules.first, <String, Object?>{
        'rule_set': <String>[adsTag],
        'action': 'reject',
      });
    });

    test('writes nothing while the list is not on disk', () {
      final section = _build(DnsSettings.defaults, routing: policy);

      expect(section.containsKey('rules'), isFalse);
    });

    test('writes nothing while the feature is off', () {
      final section = _build(
        DnsSettings.defaults,
        ruleSets: const <String>{adsTag},
      );

      expect(section.containsKey('rules'), isFalse);
    });

    test('answers before FakeIP does', () {
      // FakeIP matches every A and AAAA query there is. Behind it the block
      // would never be reached, and an advertising name would resolve to a
      // fake address that only the route section refuses afterwards.
      final section = _build(
        const DnsSettings(fakeIp: true),
        routing: policy,
        ruleSets: const <String>{adsTag},
      );
      final rules =
          (section['rules']! as List<Object?>).cast<Map<String, Object?>>();

      expect(rules.first['action'], 'reject');
      expect(rules.last['server'], 'dns-fake');
    });

    test('applies outside rules mode, like the route section', () {
      final section = _build(
        DnsSettings.defaults,
        routing: const RoutingPolicy(mode: RoutingMode.global, blockAds: true),
        ruleSets: const <String>{adsTag},
      );
      final rules = section['rules']! as List<Object?>;

      expect(rules.single, <String, Object?>{
        'rule_set': <String>[adsTag],
        'action': 'reject',
      });
    });

    test('names the list the route section names', () {
      expect(RouteSectionBuilder.adsRuleSetTag, adsTag);
    });
  });
}
