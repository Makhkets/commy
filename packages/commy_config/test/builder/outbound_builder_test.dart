import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

ProxyNode _node(
  Protocol protocol,
  Map<String, Object?> params, {
  String host = 'a.example',
  int port = 443,
}) =>
    ProxyNode(
      id: 'n1',
      name: 'N',
      protocol: protocol,
      host: host,
      port: port,
      params: params,
    );

Map<String, Object?> _build(ProxyNode node) =>
    OutboundBuilder.build(node: node, tag: 'proxy-out');

void main() {
  group('OutboundBuilder vless', () {
    test('never writes spider_x, which the core has no field for', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'security': 'reality',
          'sni': 's.example',
          'pbk': 'KEY',
          'sid': 'ab12',
          'spx': '/spider',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;
      final reality = tls['reality']! as Map<String, Object?>;

      expect(reality.keys.toList()..sort(), <String>[
        'enabled',
        'public_key',
        'short_id',
      ]);
      expect(outbound.containsKey('spider_x'), isFalse);
      expect(tls.containsKey('spider_x'), isFalse);
    });

    test('turns uTLS on for reality even when no fingerprint was given', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'security': 'reality',
          'sni': 's.example',
          'pbk': 'KEY',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls['utls'], <String, Object?>{
        'enabled': true,
        'fingerprint': 'chrome',
      });
    });

    test('omits packet_encoding so the core picks its own default', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{'uuid': 'u'}),
      );

      expect(outbound.containsKey('packet_encoding'), isFalse);
      expect(outbound.containsKey('tls'), isFalse);
    });

    test('fills the server name from the host when there is no sni', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'security': 'tls',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls['server_name'], 'a.example');
    });

    test('does not send an address literal as the server name', () {
      final outbound = _build(
        _node(
          Protocol.vless,
          <String, Object?>{'uuid': 'u', 'security': 'tls'},
          host: '203.0.113.7',
        ),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls.containsKey('server_name'), isFalse);
    });

    test('refuses a short id that is not hex', () {
      expect(
        () => _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'security': 'reality',
            'sni': 's.example',
            'pbk': 'KEY',
            'sid': 'not-hex!',
          }),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
    });

    test('refuses a node with no user id', () {
      expect(
        () => _build(_node(Protocol.vless, const <String, Object?>{})),
        throwsA(isA<ConfigBuildException>()),
      );
    });
  });

  group('OutboundBuilder transports', () {
    test('writes a websocket transport with its host header', () {
      final outbound = _build(
        _node(Protocol.trojan, <String, Object?>{
          'password': 'pw',
          'type': 'ws',
          'security': 'tls',
          'path': '/ray',
          'host': 'cdn.example',
        }),
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'ws',
        'path': '/ray',
        'headers': <String, Object?>{'Host': 'cdn.example'},
      });
    });

    test('splits the xray early-data window out of the path', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'ws',
          'path': '/ray?ed=2048',
        }),
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'ws',
        'path': '/ray',
        'max_early_data': 2048,
        'early_data_header_name': 'Sec-WebSocket-Protocol',
      });
    });

    test('writes a grpc service name without slashes', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'grpc',
          'serviceName': '/svc/',
        }),
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'grpc',
        'service_name': 'svc',
      });
    });

    test('http takes a host list, httpupgrade takes a host string', () {
      final asHttp = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'http',
          'host': 'a.example,b.example',
        }),
      );
      final asUpgrade = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'httpupgrade',
          'host': 'a.example,b.example',
        }),
      );

      expect(
        (asHttp['transport']! as Map<String, Object?>)['host'],
        <String>['a.example', 'b.example'],
      );
      expect(
        (asUpgrade['transport']! as Map<String, Object?>)['host'],
        'a.example',
      );
    });

    test('refuses a transport the core does not have', () {
      expect(
        () => _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'type': 'xhttp',
          }),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
    });
  });

  group('OutboundBuilder other protocols', () {
    test('vmess always names a cipher', () {
      final outbound = _build(
        _node(Protocol.vmess, <String, Object?>{'uuid': 'u'}),
      );

      expect(outbound['security'], 'auto');
      expect(outbound.containsKey('alter_id'), isFalse);
    });

    test('vmess keeps a non-zero alter id', () {
      final outbound = _build(
        _node(Protocol.vmess, <String, Object?>{'uuid': 'u', 'alterId': '64'}),
      );

      expect(outbound['alter_id'], 64);
    });

    test('shadowsocks writes the plugin arguments', () {
      final outbound = _build(
        _node(Protocol.shadowsocks, <String, Object?>{
          'method': 'aes-256-gcm',
          'password': 'pw',
          'plugin': 'obfs-local',
          'pluginOpts': 'obfs=http',
        }),
      );

      expect(outbound['method'], 'aes-256-gcm');
      expect(outbound['plugin'], 'obfs-local');
      expect(outbound['plugin_opts'], 'obfs=http');
    });

    test('hysteria2 normalises a port hopping range', () {
      final outbound = _build(
        _node(Protocol.hysteria2, <String, Object?>{
          'password': 'pw',
          'serverPorts': '2080-3000',
        }),
      );

      expect(outbound['server_ports'], <String>['2080:3000']);
    });

    test('hysteria2 and tuic are always tls', () {
      final hysteria = _build(
        _node(Protocol.hysteria2, <String, Object?>{'password': 'pw'}),
      );
      final tuic = _build(
        _node(Protocol.tuic, <String, Object?>{'uuid': 'u', 'password': 'pw'}),
      );

      expect((hysteria['tls']! as Map<String, Object?>)['enabled'], isTrue);
      expect((tuic['tls']! as Map<String, Object?>)['enabled'], isTrue);
    });

    test('tuic drops a congestion controller the core does not know', () {
      final outbound = _build(
        _node(Protocol.tuic, <String, Object?>{
          'uuid': 'u',
          'congestion_control': 'magic',
        }),
      );

      expect(outbound.containsKey('congestion_control'), isFalse);
    });

    test('shadowtls refuses version 3 with no password', () {
      expect(
        () => _build(
          _node(Protocol.shadowtls, <String, Object?>{'version': '3'}),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
    });

    test('wireguard becomes an endpoint with one peer', () {
      final endpoint = _build(
        _node(
          Protocol.wireguard,
          <String, Object?>{
            'private_key': 'PK',
            'peerPublicKey': 'PEER',
            'localAddress': '10.0.0.2/32,fd00::2/128',
            'reserved': '1,2,3',
            'keepAlive': '25',
            'mtu': '1420',
          },
          host: 'wg.example',
          port: 51820,
        ),
      );
      final peers = endpoint['peers']! as List<Object?>;
      final peer = peers.single! as Map<String, Object?>;

      expect(OutboundBuilder.isEndpoint(Protocol.wireguard), isTrue);
      expect(endpoint['address'], <String>['10.0.0.2/32', 'fd00::2/128']);
      expect(endpoint['private_key'], 'PK');
      expect(endpoint['mtu'], 1420);
      expect(peer['address'], 'wg.example');
      expect(peer['port'], 51820);
      expect(peer['public_key'], 'PEER');
      expect(peer['allowed_ips'], <String>['0.0.0.0/0', '::/0']);
      expect(peer['persistent_keepalive_interval'], 25);
      expect(peer['reserved'], <int>[1, 2, 3]);
    });

    test('wireguard refuses reserved bytes outside 0..255', () {
      expect(
        () => _build(
          _node(Protocol.wireguard, <String, Object?>{
            'private_key': 'PK',
            'peerPublicKey': 'PEER',
            'localAddress': '10.0.0.2/32',
            'reserved': '1,2,300',
          }),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
    });

    test('socks writes a version and only sends a password with a user', () {
      final anonymous = _build(
        _node(Protocol.socks, const <String, Object?>{}),
      );
      final authenticated = _build(
        _node(Protocol.socks, <String, Object?>{
          'username': 'u',
          'password': 'p',
        }),
      );

      expect(anonymous['version'], '5');
      expect(anonymous.containsKey('username'), isFalse);
      expect(authenticated['username'], 'u');
      expect(authenticated['password'], 'p');
    });
  });
}
