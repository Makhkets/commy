import 'dart:convert';
import 'dart:io';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// The Dart half of a two-sided check; the Go half is
/// `core/internal/singbox/core_accepts_test.go`.
///
/// A value the builder writes and the core refuses does not cost one server:
/// the core refuses the document, and every server in it goes down with the
/// one. Each case here is a link as panels and other clients write it, with
/// the kind of value that used to get through — a flow, a cipher, a plugin,
/// a port hop, an interface address — and the object the builder makes of it.
/// The same goes for routing rules as users and other clients write them.
/// This test holds the builder to the fixture; the Go test hands every object
/// in the fixture to sing-box itself and fails on any it would not construct.
///
/// After a deliberate change to what the builder writes, regenerate with
///
/// ```bash
/// COMMY_UPDATE_FIXTURES=1 dart test test/builder/core_accepts_contract_test.dart
/// ```
///
/// and run the Go half before committing the new fixture.
void main() {
  // `dart test` runs from the package directory.
  final fixture = File('../../core/internal/singbox/testdata/dart_nodes.json');
  final update = Platform.environment['COMMY_UPDATE_FIXTURES'] == '1';
  final parser = CommyLinkParser();

  Map<String, Object?> buildFrom(String link) {
    final outcome = parser.parse(link).valueOrNull;
    expect(outcome?.failures, isEmpty, reason: 'the link did not parse');
    expect(outcome?.nodes, hasLength(1));
    return OutboundBuilder.build(node: outcome!.nodes.single, tag: 'out');
  }

  Map<String, Object?> dnsFrom(DnsSettings dns, RoutingPolicy routing) =>
      DnsSectionBuilder.build(
        dns: dns,
        routing: routing,
        platform: ConfigPlatform.android,
        availableRuleSets: const <String>{},
      );

  Map<String, Object?> routeFrom(
    List<String> matchers, {
    bool fakeIp = false,
  }) =>
      RouteSectionBuilder.build(
        routing: RoutingPolicy(
          rules: <RoutingRule>[
            for (final (index, matcher) in matchers.indexed)
              RoutingRule(
                id: 'r$index',
                matcher: matcher,
                action: RuleAction.values[index % RuleAction.values.length],
                sortIndex: index,
              ),
          ],
        ),
        platform: ConfigPlatform.android,
        availableRuleSets: const <String>{},
        ruleSetDirectory: null,
        dns: DnsSettings(fakeIp: fakeIp),
        warnings: <RoutingWarning>[],
      );

  Map<String, Object?> loopbackProxy() => InboundSectionBuilder.mixed(
        settings: const AppSettings(ipCheckUrl: 'https://ip.example/json'),
        localAuth: const LocalProxyAuth(password: '00112233445566778899aabb'),
      );

  if (update) {
    test('regenerates the fixture', () {
      final document = <String, Object?>{
        '_comment': 'Written by $_dartHalf; read by $_goHalf. Every object '
            'must be one sing-box constructs.',
        'cases': <Object?>[
          for (final (name, link) in _links)
            <String, Object?>{
              'name': name,
              'link': link,
              'kind': buildFrom(link)['type'] == Protocol.wireguard.wireName
                  ? 'endpoint'
                  : 'outbound',
              'object': buildFrom(link),
            },
          for (final (name, dns, routing) in _resolvers)
            <String, Object?>{
              'name': name,
              'kind': 'dns',
              'object': dnsFrom(dns, routing),
            },
          for (final (name, matchers, fakeIp) in _routes)
            <String, Object?>{
              'name': name,
              'kind': 'route',
              'object': routeFrom(matchers, fakeIp: fakeIp),
            },
          <String, Object?>{
            'name': _loopbackProxy,
            'kind': 'inbound',
            'object': loopbackProxy(),
          },
        ],
      };
      fixture.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
      );
    });
    return;
  }

  final document =
      jsonDecode(fixture.readAsStringSync()) as Map<String, Object?>;
  final cases = (document['cases']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .toList(growable: false);

  test('the fixture holds every case below, and nothing else', () {
    expect(
      <String>[for (final entry in cases) '${entry['name']}'],
      <String>[
        for (final (name, _) in _links) name,
        for (final (name, _, _) in _resolvers) name,
        for (final (name, _, _) in _routes) name,
        _loopbackProxy,
      ],
    );
  });

  final links = Map<String, String>.fromEntries(
    _links.map((link) => MapEntry<String, String>(link.$1, link.$2)),
  );
  final resolvers = <String, Map<String, Object?> Function()>{
    for (final (name, dns, routing) in _resolvers)
      name: () => dnsFrom(dns, routing),
  };
  final routes = <String, Map<String, Object?> Function()>{
    for (final (name, matchers, fakeIp) in _routes)
      name: () => routeFrom(matchers, fakeIp: fakeIp),
  };
  for (final entry in cases) {
    final name = '${entry['name']}';
    test('the core is handed what the fixture promises: $name', () {
      final link = links[name];
      final dns = resolvers[name];
      final route = routes[name];
      expect(
        link != null
            ? buildFrom(link)
            : dns != null
                ? dns()
                : route != null
                    ? route()
                    : loopbackProxy(),
        entry['object'],
      );
    });
  }
}

/// The loopback proxy of the IP check, which asks for a password.
const String _loopbackProxy = 'The loopback proxy, with its user';

/// DNS sections, for the resolvers the core has to be told how to find and
/// the rules a routing policy writes into the section.
const List<(String, DnsSettings, RoutingPolicy)> _resolvers =
    <(String, DnsSettings, RoutingPolicy)>[
  (
    'DNS, the direct resolver by name over HTTPS',
    DnsSettings(
      remote: 'https://dns.google/dns-query',
      direct: 'https://cloudflare-dns.com/dns-query',
    ),
    RoutingPolicy.defaults,
  ),
  (
    'DNS, the direct resolver by name over TLS, FakeIP on',
    DnsSettings(direct: 'tls://dns.quad9.net', fakeIp: true),
    RoutingPolicy.defaults,
  ),
  (
    'DNS, FakeIP on, a proxied exception above a direct and a blocked rule',
    DnsSettings(fakeIp: true),
    RoutingPolicy(
      rules: <RoutingRule>[
        RoutingRule(
          id: 'r0',
          matcher: 'domain:example.com',
          action: RuleAction.proxy,
        ),
        RoutingRule(
          id: 'r1',
          matcher: 'domain_suffix:com',
          action: RuleAction.direct,
          sortIndex: 1,
        ),
        RoutingRule(
          id: 'r2',
          matcher: 'domain_keyword:ads',
          action: RuleAction.block,
          sortIndex: 2,
        ),
      ],
    ),
  ),
  (
    'DNS, Direct mode, the direct resolver answering the rest',
    DnsSettings.defaults,
    RoutingPolicy(mode: RoutingMode.direct),
  ),
];

/// Route sections, for the rules the core parses before anything connects.
///
/// Each list is rules as users type them and other clients write them —
/// Xray's port range with a dash, an expression with Go's inline flag, a
/// bare address — and whether FakeIP is on, which adds a lookup ahead of
/// the first rule on addresses.
const List<(String, List<String>, bool)> _routes =
    <(String, List<String>, bool)>[
  (
    'Route, rules as other clients write them',
    <String>[
      'port_range:1000-2000',
      'port_range:443,3000:',
      r'regex:(?i)^ads\.',
      'ip_cidr:10.0.0.0/8,192.0.2.1',
      'port:443,8443',
    ],
    false,
  ),
  (
    'Route, FakeIP on, a rule on names and one on addresses',
    <String>['domain_suffix:example.org', 'ip_cidr:203.0.113.0/24'],
    true,
  ),
];

const String _dartHalf =
    'packages/commy_config/test/builder/core_accepts_contract_test.dart';
const String _goHalf = 'core/internal/singbox/core_accepts_test.go';

/// Real-looking links whose values used to reach the core as they were.
///
/// Keys are fixed test bytes, hosts are `example.com`: rule R2 applies to
/// fixtures as much as to logs.
const List<(String, String)> _links = <(String, String)>[
  (
    'VLESS REALITY with Xray vision-udp443',
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '?security=reality&sni=www.example.com'
        '&pbk=xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k&sid=ab12cd34'
        '&fp=chrome&flow=xtls-rprx-vision-udp443&type=tcp#vision-udp443',
  ),
  (
    'VLESS with the flow written as none',
    'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '?security=tls&sni=example.com&flow=none&type=ws&path=%2Fws'
        '&host=example.com#flow-none',
  ),
  (
    'Shadowsocks 2022, one key',
    'ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9EeEFS'
        'RWhNVUZSWVhHQmthR3h3ZEhoOD0@example.com:8388#ss2022',
  ),
  (
    'Shadowsocks 2022, two keys',
    'ss://MjAyMi1ibGFrZTMtYWVzLTEyOC1nY206QUFFQ0F3UUZCZ2NJQ1FvTERBME9Edz09'
        'OkFBRUNBd1FGQmdjSUNRb0xEQTBPRHc9PQ@example.com:8388#ss2022-eih',
  ),
  (
    'Shadowsocks with the plugin called simple-obfs',
    'ss://YWVzLTEyOC1nY206cGFzcy13b3Jk@example.com:8388'
        '?plugin=simple-obfs%3Bobfs%3Dhttp%3Bobfs-host%3Dexample.com'
        '#simple-obfs',
  ),
  (
    'Shadowsocks with v2ray-plugin over websocket and TLS',
    'ss://YWVzLTEyOC1nY206cGFzcy13b3Jk@example.com:443'
        '?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dexample.com'
        '%3Bpath%3D%2Fws%3Btls#v2ray-plugin',
  ),
  (
    'Shadowsocks with the Xray spelling of ChaCha20',
    'ss://Y2hhY2hhMjAtcG9seTEzMDU6cGFzcy13b3Jk@example.com:8388#chacha',
  ),
  (
    'Hysteria 2 hopping over a single port',
    'hysteria2://pass-word@example.com:443?sni=example.com&mport=443'
        '#hy2-single',
  ),
  (
    'Hysteria 2 hopping over a range, with salamander',
    'hy2://pass-word@example.com:443?sni=example.com&mport=20000-30000'
        '&obfs=salamander&obfs-password=secret#hy2-range',
  ),
  (
    'WireGuard with bare interface addresses',
    'wireguard://CAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHkg%3D'
        '@example.com:51820'
        '?publickey=ZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXp7fH1%2Bf4CBgoM%3D'
        '&address=10.0.0.2,fd00::2&mtu=1420#wg-bare',
  ),
];
