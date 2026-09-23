import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _reality = ProxyNode(
  id: 'cz',
  name: 'Czech Republic',
  protocol: Protocol.vless,
  host: 'cz.example.net',
  port: 8443,
  params: <String, Object?>{
    'uuid': '3d1f6a30-0b1c-4a2b-9f7e-8c5d4e3b2a10',
    'flow': 'xtls-rprx-vision',
    'type': 'tcp',
    'security': 'reality',
    'sni': 'www.microsoft.com',
    'pbk': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
    'sid': 'a1b2c3d4',
  },
);

const _wireguard = ProxyNode(
  id: 'wg',
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

const _nowhere = ProxyNode(
  id: 'notice',
  name: 'App not supported',
  protocol: Protocol.vless,
  host: '0.0.0.0',
  port: 1,
);

Map<String, Object?> _probe(List<ProxyNode> nodes, {DnsSettings? dns}) {
  final result = const SingBoxConfigBuilder().buildProbe(
    nodes: nodes,
    dns: dns ?? DnsSettings.defaults,
  );
  expect(result.failureOrNull, isNull, reason: '${result.failureOrNull}');
  return result.valueOrNull!.document;
}

/// The document the "Ping" setting's GET runs on: the servers' outbounds and
/// nothing a tunnel would need.
void main() {
  test('carries each outbound exactly as the tunnel does', () {
    final tunnel = const SingBoxConfigBuilder()
        .build(
          SingBoxBuildRequest.single(
            node: _reality,
            routing: RoutingPolicy.defaults,
            dns: DnsSettings.defaults,
            settings: AppSettings.defaults,
            platform: ConfigPlatform.android,
          ),
        )
        .valueOrNull!
        .config
        .document;
    final inTunnel = (tunnel['outbounds']! as List<Object?>).firstWhere(
      (item) => (item! as Map<String, Object?>)['tag'] == 'node-cz',
    );

    final probe = _probe(<ProxyNode>[_reality]);

    expect(probe['outbounds'], <Object?>[inTunnel]);
  });

  test('has no inbound, no group, no log and no rules', () {
    final probe = _probe(<ProxyNode>[_reality]);

    expect(probe.containsKey('inbounds'), isFalse);
    expect(probe.containsKey('experimental'), isFalse);
    expect(probe['log'], <String, Object?>{'disabled': true});
    final route = probe['route']! as Map<String, Object?>;
    expect(route.containsKey('rules'), isFalse);
    final types = (probe['outbounds']! as List<Object?>)
        .map((item) => (item! as Map<String, Object?>)['type']);
    expect(types, isNot(contains('selector')));
    expect(types, isNot(contains('urltest')));
  });

  test('resolves server names with the direct resolver, as the tunnel does',
      () {
    final probe = _probe(
      <ProxyNode>[_reality],
      dns: const DnsSettings(direct: 'udp://77.88.8.8'),
    );

    final dns = probe['dns']! as Map<String, Object?>;
    final server = (dns['servers']! as List<Object?>).single!
        as Map<String, Object?>;
    expect(server['tag'], SingBoxTags.dnsDirect);
    expect(server['type'], 'udp');
    expect(server['server'], '77.88.8.8');
    final route = probe['route']! as Map<String, Object?>;
    expect(route['default_domain_resolver'], <String, Object?>{
      'server': SingBoxTags.dnsDirect,
    });
  });

  test('puts wireguard among the endpoints', () {
    final probe = _probe(<ProxyNode>[_reality, _wireguard]);

    final endpoints = probe['endpoints']! as List<Object?>;
    expect((endpoints.single! as Map<String, Object?>)['tag'], 'node-wg');
  });

  test('leaves out what cannot be dialled, and the duplicates', () {
    final probe = _probe(<ProxyNode>[_reality, _nowhere, _reality]);

    final tags = (probe['outbounds']! as List<Object?>)
        .map((item) => (item! as Map<String, Object?>)['tag']);
    expect(tags, <String>['node-cz']);
  });

  test('with nothing left to measure it is an error', () {
    final result = const SingBoxConfigBuilder().buildProbe(
      nodes: const <ProxyNode>[_nowhere],
      dns: DnsSettings.defaults,
    );

    expect(result.failureOrNull, isA<ConfigInvalidFailure>());
  });
}
