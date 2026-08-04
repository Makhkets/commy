import 'dart:convert';
import 'dart:io';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _realityNode = ProxyNode(
  id: 'reality-1',
  name: 'NL-03',
  protocol: Protocol.vless,
  host: 'nl-03.example.net',
  port: 443,
  params: <String, Object?>{
    'uuid': '3d1f6a30-0b1c-4a2b-9f7e-8c5d4e3b2a10',
    'flow': 'xtls-rprx-vision',
    'type': 'tcp',
    'security': 'reality',
    'sni': 'www.microsoft.com',
    'fp': 'chrome',
    'pbk': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
    'sid': 'a1b2c3d4',
    'spx': '/',
  },
);

const _hysteriaNode = ProxyNode(
  id: 'hy2-1',
  name: 'Fast',
  protocol: Protocol.hysteria2,
  host: '203.0.113.10',
  port: 8443,
  params: <String, Object?>{
    'password': 's3cret',
    'sni': 'example.com',
    'obfs': 'salamander',
    'obfs-password': 'obf',
    'upMbps': 100,
    'downMbps': 500,
    'allowInsecure': true,
  },
);

Map<String, Object?> _golden(String name) {
  final raw = File('test/golden/$name.json').readAsStringSync();
  return jsonDecode(raw) as Map<String, Object?>;
}

CoreConfig _build(SingBoxBuildRequest request) {
  final result = const SingBoxConfigBuilder().build(request);
  final failure = result.failureOrNull;
  expect(failure, isNull, reason: '$failure');
  return result.valueOrNull!.config;
}

void main() {
  group('SingBoxConfigBuilder golden', () {
    test('vless + reality on android matches the checked-in document', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );

      expect(config.document, _golden('vless_reality_android'));
    });

    test('hysteria2 + fakeip on windows matches the checked-in document', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _hysteriaNode,
          routing: const RoutingPolicy(
            rules: <RoutingRule>[
              RoutingRule(
                id: 'r1',
                matcher: 'domain_suffix:ads.example',
                action: RuleAction.block,
              ),
              RoutingRule(
                id: 'r2',
                matcher: 'geoip:private',
                action: RuleAction.direct,
                sortIndex: 1,
              ),
              RoutingRule(
                id: 'r3',
                matcher: 'process_name:curl',
                action: RuleAction.direct,
                sortIndex: 2,
              ),
            ],
            bypassLan: false,
          ),
          dns: const DnsSettings(fakeIp: true),
          settings: const AppSettings(
            allowLan: true,
            logLevel: LogLevel.debug,
          ),
          platform: ConfigPlatform.windows,
          includeClashApi: true,
          clashApi: const ClashApiOptions(secret: 'testsecret'),
        ),
      );

      expect(config.document, _golden('hysteria2_fakeip_windows'));
    });

    test('the same input encodes byte for byte the same way twice', () {
      SingBoxBuildRequest request() => SingBoxBuildRequest.single(
            node: _realityNode,
            routing: RoutingPolicy.defaults,
            dns: DnsSettings.defaults,
            settings: AppSettings.defaults,
            platform: ConfigPlatform.android,
          );

      expect(_build(request()).encode(), _build(request()).encode());
    });
  });

  group('SingBoxConfigBuilder structure', () {
    test('always defines the selector group SwitchNodeUseCase points at', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final outbounds = config.document['outbounds']! as List<Object?>;
      final selector = outbounds.firstWhere(
        (item) => (item! as Map<String, Object?>)['tag'] == 'proxy',
      )! as Map<String, Object?>;

      expect(SingBoxTags.proxyGroup, SwitchNodeUseCase.defaultGroupTag);
      expect(selector['type'], 'selector');
      expect(selector['default'], SingBoxTags.forNode(_realityNode));
    });

    test('puts wireguard in endpoints, not in outbounds', () {
      const node = ProxyNode(
        id: 'wg-1',
        name: 'WG',
        protocol: Protocol.wireguard,
        host: 'wg.example.com',
        port: 51820,
        params: <String, Object?>{
          'private_key': 'PK',
          'peerPublicKey': 'PEER',
          'localAddress': '10.0.0.2/32',
        },
      );
      final config = _build(
        SingBoxBuildRequest.single(
          node: node,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.linux,
        ),
      );
      final endpoints = config.document['endpoints']! as List<Object?>;
      final endpoint = endpoints.single! as Map<String, Object?>;
      final outbounds = config.document['outbounds']! as List<Object?>;

      expect(endpoint['type'], 'wireguard');
      expect(endpoint['tag'], 'node-wg-1');
      expect(endpoint['address'], <String>['10.0.0.2/32']);
      expect(endpoint['peers']! as List<Object?>, hasLength(1));
      expect(
        outbounds.every(
          (item) => (item! as Map<String, Object?>)['type'] != 'wireguard',
        ),
        isTrue,
      );
    });

    test('never writes the removed inbound sniff field', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final inbounds = config.document['inbounds']! as List<Object?>;
      final tun = inbounds.first! as Map<String, Object?>;
      final rules = (config.document['route']!
          as Map<String, Object?>)['rules']! as List<Object?>;

      expect(tun.containsKey('sniff'), isFalse);
      expect(tun.containsKey('inet4_address'), isFalse);
      expect(tun.containsKey('inet6_address'), isFalse);
      expect(
        (rules.first! as Map<String, Object?>)['action'],
        'sniff',
      );
    });

    test('always keeps our own package out of the tunnel on android', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(
            perAppMode: PerAppMode.exclude,
            perAppPackages: <String>['com.example.other'],
          ),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final inbounds = config.document['inbounds']! as List<Object?>;
      final tun = inbounds.first! as Map<String, Object?>;

      expect(
        tun['exclude_package'],
        <String>['dev.commy.app', 'com.example.other'],
      );
    });

    test('drops our own package from an include list', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(
            perAppMode: PerAppMode.include,
            perAppPackages: <String>['dev.commy.app', 'com.example.browser'],
          ),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final inbounds = config.document['inbounds']! as List<Object?>;
      final tun = inbounds.first! as Map<String, Object?>;

      expect(tun['include_package'], <String>['com.example.browser']);
    });

    test('pins the stack to gvisor on ios whatever the setting says', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: const AppSettings(tunStack: TunStack.system),
          platform: ConfigPlatform.ios,
        ),
      );
      final inbounds = config.document['inbounds']! as List<Object?>;

      expect((inbounds.first! as Map<String, Object?>)['stack'], 'gvisor');
    });

    test('refuses to expose the clash api on mobile', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.ios,
          includeClashApi: true,
          clashApi: const ClashApiOptions(secret: 'testsecret'),
        ),
      );
      final experimental =
          config.document['experimental']! as Map<String, Object?>;

      expect(experimental.containsKey('clash_api'), isFalse);
    });

    test('binds the clash api to loopback only', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.macos,
          includeClashApi: true,
          clashApi: const ClashApiOptions(secret: 'testsecret', port: 19090),
        ),
      );
      final experimental =
          config.document['experimental']! as Map<String, Object?>;
      final api = experimental['clash_api']! as Map<String, Object?>;

      expect(api['external_controller'], '127.0.0.1:19090');
      expect(api['secret'], 'testsecret');
    });

    test('points final at direct when the mode is direct', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(mode: RoutingMode.direct),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final route = config.document['route']! as Map<String, Object?>;

      expect(route['final'], 'direct');
    });

    test('ignores the rule list in global mode', () {
      final config = _build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(
            mode: RoutingMode.global,
            rules: <RoutingRule>[
              RoutingRule(
                id: 'r1',
                matcher: 'domain_suffix:example.com',
                action: RuleAction.direct,
              ),
            ],
          ),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final route = config.document['route']! as Map<String, Object?>;
      final rules = route['rules']! as List<Object?>;

      expect(route['final'], 'proxy');
      bool hasDomainRule(Object? item) =>
          (item! as Map<String, Object?>).containsKey('domain_suffix');

      expect(rules.any(hasDomainRule), isFalse);
    });

    test('adds a urltest group when auto is on and there is a choice', () {
      const second = ProxyNode(
        id: 'reality-2',
        name: 'NL-04',
        protocol: Protocol.vless,
        host: 'nl-04.example.net',
        port: 443,
        params: <String, Object?>{'uuid': 'u', 'security': 'none'},
      );
      final result = const SingBoxConfigBuilder().build(
        const SingBoxBuildRequest(
          nodes: <ProxyNode>[_realityNode, second],
          selectedNodeId: 'reality-1',
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
          autoSelect: true,
        ),
      );
      final document = result.valueOrNull!.config.document;
      final outbounds = document['outbounds']! as List<Object?>;
      final tags = <Object?>[
        for (final item in outbounds) (item! as Map<String, Object?>)['tag'],
      ];
      final selector = outbounds.firstWhere(
        (item) => (item! as Map<String, Object?>)['tag'] == 'proxy',
      )! as Map<String, Object?>;

      expect(tags, contains('auto'));
      expect(selector['default'], 'auto');
      expect(
        selector['outbounds'],
        <String>['auto', 'node-reality-1', 'node-reality-2'],
      );
    });
  });

  group('SingBoxConfigBuilder validation', () {
    test('refuses an empty node list', () {
      final result = const SingBoxConfigBuilder().build(
        const SingBoxBuildRequest(
          nodes: <ProxyNode>[],
          selectedNodeId: 'x',
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('refuses a selection that is not in the list', () {
      final result = const SingBoxConfigBuilder().build(
        const SingBoxBuildRequest(
          nodes: <ProxyNode>[_realityNode],
          selectedNodeId: 'somewhere-else',
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('refuses a node with an impossible port', () {
      const broken = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.vless,
        host: 'a.example',
        port: 70000,
        params: <String, Object?>{'uuid': 'u'},
      );
      final result = const SingBoxConfigBuilder().build(
        SingBoxBuildRequest.single(
          node: broken,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('refuses a Reality node with no public key', () {
      const broken = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.vless,
        host: 'a.example',
        port: 443,
        params: <String, Object?>{
          'uuid': 'u',
          'security': 'reality',
          'sni': 's.example',
        },
      );
      final result = const SingBoxConfigBuilder().build(
        SingBoxBuildRequest.single(
          node: broken,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('drops a geosite rule when the rule set is not on disk', () {
      final result = const SingBoxConfigBuilder().build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(
            rules: <RoutingRule>[
              RoutingRule(
                id: 'r1',
                matcher: 'geosite:ru',
                action: RuleAction.direct,
              ),
            ],
          ),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final built = result.valueOrNull!;
      final route = built.config.document['route']! as Map<String, Object?>;

      expect(built.hasWarnings, isTrue);
      expect(route.containsKey('rule_set'), isFalse);
    });

    test('writes a local rule set when the file is on disk', () {
      final result = const SingBoxConfigBuilder().build(
        SingBoxBuildRequest.single(
          node: _realityNode,
          routing: const RoutingPolicy(
            rules: <RoutingRule>[
              RoutingRule(
                id: 'r1',
                matcher: 'geosite:ru',
                action: RuleAction.direct,
              ),
            ],
          ),
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
          ruleSetDirectory: '/data/rulesets',
          availableRuleSets: const <String>{'geosite-ru'},
        ),
      );
      final built = result.valueOrNull!;
      final route = built.config.document['route']! as Map<String, Object?>;
      final ruleSets = route['rule_set']! as List<Object?>;

      expect(built.hasWarnings, isFalse);
      expect(
        ruleSets.single,
        <String, Object?>{
          'type': 'local',
          'tag': 'geosite-ru',
          'format': 'binary',
          'path': '/data/rulesets/geosite-ru.srs',
        },
      );
    });
  });
}
