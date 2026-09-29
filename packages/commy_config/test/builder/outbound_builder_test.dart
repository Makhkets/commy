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

/// A REALITY public key the core can decode: 32 bytes, URL-safe base64.
const _realityKey = 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k';

Map<String, Object?> _build(ProxyNode node) =>
    OutboundBuilder.build(node: node, tag: 'proxy-out');

void main() {
  group('OutboundBuilder values the core would refuse whole', () {
    // The core checks these when it builds the outbound, and a refusal there
    // is a refusal of the whole document: no server connects. Here they leave
    // one server out, with a reason, or are rewritten into what they mean.
    const key = _realityKey;

    Map<String, Object?> tlsOf(Map<String, Object?> params) => _build(
          _node(
            Protocol.vless,
            <String, Object?>{'uuid': 'u', ...params},
          ),
        )['tls']! as Map<String, Object?>;

    Map<String, Object?> realityOf(Map<String, Object?> params) =>
        tlsOf(<String, Object?>{
          'security': 'reality',
          'sni': 's.example',
          ...params,
        })['reality']! as Map<String, Object?>;

    test('a fingerprint in capitals is the same fingerprint', () {
      final tls = tlsOf(<String, Object?>{'security': 'tls', 'fp': 'Firefox'});

      expect(tls['utls'], <String, Object?>{
        'enabled': true,
        'fingerprint': 'firefox',
      });
    });

    test('a fingerprint the core does not have becomes Chrome', () {
      for (final name in <String>['randomizednoalpn', 'hellochrome_120']) {
        final tls = tlsOf(<String, Object?>{'security': 'tls', 'fp': name});

        expect(
          (tls['utls']! as Map<String, Object?>)['fingerprint'],
          'chrome',
          reason: name,
        );
      }
    });

    test('a Reality key in standard or padded base64 is rewritten', () {
      const standard = 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k=';

      expect(realityOf(<String, Object?>{'pbk': standard})['public_key'], key);
      expect(
        realityOf(
          <String, Object?>{'pbk': 'a+b/${key.substring(4)}'},
        )['public_key'],
        'a-b_${key.substring(4)}',
      );
    });

    test('a Reality key is read as Go reads it, stray low bits and all', () {
      // The last character carries two bits no key uses; Go ignores them,
      // Dart's decoder would not.
      final stray = '${key.substring(0, 42)}l';

      expect(realityOf(<String, Object?>{'pbk': stray})['public_key'], stray);
    });

    test('a Reality key that is not one leaves the server out', () {
      for (final bad in <String>['KEY', '${key}AAAA', '!!!']) {
        expect(
          () => realityOf(<String, Object?>{'pbk': bad}),
          throwsA(
            isA<ConfigBuildException>().having(
              (error) => error.reason,
              'reason',
              contains('public key'),
            ),
          ),
          reason: bad,
        );
      }
    });

    test('a short id of odd length leaves the server out', () {
      expect(
        () => realityOf(<String, Object?>{'pbk': key, 'sid': 'abc'}),
        throwsA(isA<ConfigBuildException>()),
      );
      expect(
        realityOf(<String, Object?>{'pbk': key, 'sid': 'abcd'})['short_id'],
        'abcd',
      );
    });
  });

  group('OutboundBuilder values only one server should pay for', () {
    // The same class as the group above, for the protocol fields: a flow, a
    // cipher, a plugin, a hop range, an interface address. What means
    // something the core knows is rewritten into it; the rest leaves this one
    // server out. core_accepts_contract_test.dart holds the rewritten forms
    // to what sing-box itself constructs.
    Matcher leftOut(String reason) => throwsA(
          isA<ConfigBuildException>().having(
            (error) => error.reason,
            'reason',
            contains(reason),
          ),
        );

    Map<String, Object?> ss(Map<String, Object?> params) => _build(
          _node(Protocol.shadowsocks, <String, Object?>{
            'method': 'aes-128-gcm',
            'password': 'p',
            ...params,
          }),
        );

    Map<String, Object?> hy2(Map<String, Object?> params) => _build(
          _node(Protocol.hysteria2, <String, Object?>{
            'password': 'p',
            ...params,
          }),
        );

    Map<String, Object?> wg(String addresses) => _build(
          _node(Protocol.wireguard, <String, Object?>{
            'private_key': 'k',
            'peerPublicKey': 'p',
            'localAddress': addresses,
          }),
        );

    test('a VLESS flow is vision, none, or this server out', () {
      Object? flowOf(String flow) => _build(
            _node(Protocol.vless, <String, Object?>{'uuid': 'u', 'flow': flow}),
          )['flow'];

      expect(flowOf('xtls-rprx-vision'), 'xtls-rprx-vision');
      expect(flowOf('XTLS-RPRX-VISION-UDP443'), 'xtls-rprx-vision');
      expect(flowOf('none'), isNull);
      expect(() => flowOf('xtls-rprx-direct'), leftOut('flow'));
    });

    test('a cipher the core does not register leaves the server out', () {
      expect(
        ss(<String, Object?>{'method': 'AES-256-GCM'})['method'],
        'aes-256-gcm',
      );
      expect(
        ss(<String, Object?>{'method': 'xchacha20-poly1305'})['method'],
        'xchacha20-ietf-poly1305',
      );
      expect(
        ss(<String, Object?>{'method': 'none', 'password': null})['password'],
        '',
      );
      expect(
        () => ss(<String, Object?>{'method': 'camellia-256-cfb'}),
        leftOut('cipher'),
      );
    });

    test('a 2022 cipher checks its keys the way the core decodes them', () {
      expect(
        () => ss(<String, Object?>{
          'method': '2022-blake3-aes-256-gcm',
          'password': 'not-a-key',
        }),
        leftOut('32 bytes'),
      );
      // Sixteen bytes is the AES-128 key; the AES-256 cipher wants 32.
      expect(
        () => ss(<String, Object?>{
          'method': '2022-blake3-aes-256-gcm',
          'password': 'AAECAwQFBgcICQoLDA0ODw==',
        }),
        leftOut('32 bytes'),
      );
      expect(
        () => ss(<String, Object?>{
          'method': '2022-blake3-chacha20-poly1305',
          'password': 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=:'
              'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=',
        }),
        leftOut('single key'),
      );
    });

    test('a plugin is obfs-local or v2ray-plugin, in a mode the core has', () {
      expect(ss(<String, Object?>{'plugin': 'obfs'})['plugin'], 'obfs-local');
      expect(
        () => ss(<String, Object?>{'plugin': 'shadow-tls'}),
        leftOut('plugin'),
      );
      expect(
        () => ss(<String, Object?>{
          'plugin': 'obfs-local',
          'pluginOpts': 'obfs=quic;obfs-host=a.example',
        }),
        leftOut('obfs mode'),
      );
      expect(
        () => ss(<String, Object?>{
          'plugin': 'v2ray-plugin',
          'pluginOpts': 'mode=quic;host=a.example',
        }),
        leftOut('v2ray-plugin mode'),
      );
      // An escaped separator is part of the value, not the end of it.
      expect(
        ss(<String, Object?>{
          'plugin': 'v2ray-plugin',
          'pluginOpts': r'mode=websocket;path=/a\;b',
        })['plugin'],
        'v2ray-plugin',
      );
    });

    test('a hop range is always start:end, or this server out', () {
      expect(
        hy2(<String, Object?>{'serverPorts': '443'})['server_ports'],
        <String>['443:443'],
      );
      expect(
        hy2(<String, Object?>{'serverPorts': '1000-2000, 3000:3100'})[
            'server_ports'],
        <String>['1000:2000', '3000:3100'],
      );
      for (final bad in <String>['2000-1000', '0-10', '70000', 'a-b']) {
        expect(
          () => hy2(<String, Object?>{'serverPorts': bad}),
          leftOut('port range'),
          reason: bad,
        );
      }
    });

    test('obfuscation is salamander with a password, or this server out', () {
      expect(
        hy2(<String, Object?>{'obfs': 'none'}).containsKey('obfs'),
        isFalse,
      );
      expect(
        () => hy2(<String, Object?>{'obfs': 'salamander'}),
        leftOut('no password'),
      );
      expect(
        () => hy2(<String, Object?>{'obfs': 'gfw', 'obfs-password': 'x'}),
        leftOut('obfuscation'),
      );
    });

    test('a bare WireGuard address is one host, anything else is refused', () {
      expect(
        wg('10.0.0.2, fd00::2')['address'],
        <String>['10.0.0.2/32', 'fd00::2/128'],
      );
      expect(wg('10.0.0.2/24')['address'], <String>['10.0.0.2/24']);
      for (final bad in <String>['10.0.0.256', 'host.example', '10.0.0.2/33']) {
        expect(() => wg(bad), leftOut('WireGuard address'), reason: bad);
      }
    });
  });

  group('OutboundBuilder vless', () {
    test('never writes spider_x, which the core has no field for', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'security': 'reality',
          'sni': 's.example',
          'pbk': _realityKey,
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
          'pbk': _realityKey,
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls['utls'], <String, Object?>{
        'enabled': true,
        'fingerprint': 'chrome',
      });
    });

    // Measured against Xray 26.9.9 with the pinned core: every uTLS hello
    // but Chrome's lacks the X25519MLKEM768 share the server now requires,
    // and Reality does not check the fingerprint anyway.
    test('reality always goes out with the chrome fingerprint', () {
      for (final named in <String>[
        'firefox',
        'safari',
        'ios',
        'edge',
        'android',
        '360',
        'qq',
        'random',
        'randomized',
        'chrome',
      ]) {
        final outbound = _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'security': 'reality',
            'sni': 's.example',
            'pbk': _realityKey,
            'fp': named,
          }),
        );
        final tls = outbound['tls']! as Map<String, Object?>;

        expect(
          (tls['utls']! as Map<String, Object?>)['fingerprint'],
          'chrome',
          reason: 'fp=$named',
        );
      }
    });

    test('plain TLS keeps the fingerprint the link named', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'security': 'tls',
          'sni': 's.example',
          'fp': 'firefox',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(
        (tls['utls']! as Map<String, Object?>)['fingerprint'],
        'firefox',
      );
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
            'pbk': _realityKey,
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

    test('opens tcp with an http header as a GET through the http transport',
        () {
      // Xray's TCP header sends GET; sing-box's http transport defaults to PUT.
      final node = const VlessLinkParser().parse(
        'vless://u@a.example:80?type=tcp&headerType=http'
        '&host=b.example,c.example&path=%2Fa,%2Fb#n',
      );

      expect(_build(node)['transport'], <String, Object?>{
        'type': 'http',
        'host': <String>['b.example', 'c.example'],
        'path': '/a',
        'method': 'GET',
      });
    });

    test('gives an http header with no path the root path', () {
      final outbound = _build(
        _node(Protocol.vmess, <String, Object?>{
          'uuid': 'u',
          'type': 'tcp',
          'security': 'none',
          'headerType': 'HTTP',
        }),
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'http',
        'path': '/',
        'method': 'GET',
      });
    });

    test('leaves bare tcp without a transport block', () {
      for (final header in <String?>[null, '', 'none']) {
        final outbound = _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'type': 'tcp',
            'headerType': header,
          }),
        );

        expect(outbound.containsKey('transport'), isFalse, reason: '$header');
      }
    });

    test('refuses a stored tcp http header the core cannot carry', () {
      // Over TLS the core's http transport is HTTP/2, which no Xray TCP
      // inbound with an HTTP header accepts.
      for (final params in <Map<String, Object?>>[
        <String, Object?>{'security': 'tls', 'headerType': 'http'},
        <String, Object?>{'security': 'none', 'headerType': 'srtp'},
      ]) {
        expect(
          () => _build(
            _node(Protocol.trojan, <String, Object?>{
              'password': 'p',
              'type': 'tcp',
              ...params,
            }),
          ),
          throwsA(isA<ConfigBuildException>()),
          reason: '$params',
        );
      }
    });

    test('refuses a stored vless node that asks for VLESS Encryption', () {
      expect(
        () => _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'encryption': 'mlkem768x25519plus.native.0rtt.AAAA',
          }),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
      expect(
        _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'encryption': 'none',
          }),
        ).containsKey('encryption'),
        isFalse,
      );
    });

    test('refuses a transport the core does not have', () {
      expect(
        () => _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'type': 'kcp',
          }),
        ),
        throwsA(isA<ConfigBuildException>()),
      );
    });
  });

  group('OutboundBuilder xhttp', () {
    test('writes nothing but the type when the node says nothing', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{'uuid': 'u', 'type': 'xhttp'}),
      );

      expect(outbound['transport'], <String, Object?>{'type': 'xhttp'});
    });

    test('leaves `auto` out and the path whole', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'xhttp',
          'mode': 'auto',
          'path': '/api?ed=2048',
          'host': 'a.example,b.example',
        }),
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'host': 'a.example',
        'path': '/api?ed=2048',
      });
    });

    test('refuses a node whose extra breaks a rule, naming the rule', () {
      expect(
        () => _build(
          _node(Protocol.vless, <String, Object?>{
            'uuid': 'u',
            'type': 'xhttp',
            'mode': 'stream-one',
            'extra': '{"uplinkHTTPMethod":"GET"}',
          }),
        ),
        throwsA(
          isA<ConfigBuildException>().having(
            (error) => error.reason,
            'reason',
            contains('packet-up'),
          ),
        ),
      );
    });

    test('keeps a browser fingerprint over HTTP/2', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'xhttp',
          'security': 'tls',
          'fp': 'chrome',
          'alpn': 'h2,http/1.1',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls['utls'], isNotNull);
      expect(tls['alpn'], <String>['h2', 'http/1.1']);
    });

    test('drops it over HTTP/3, where the core would refuse every dial', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'xhttp',
          'security': 'tls',
          'fp': 'chrome',
          'alpn': 'h3',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls.containsKey('utls'), isFalse);
      expect(tls['alpn'], <String>['h3']);
    });

    test('Reality is HTTP/2 whatever the ALPN says, and keeps uTLS', () {
      final outbound = _build(
        _node(Protocol.vless, <String, Object?>{
          'uuid': 'u',
          'type': 'xhttp',
          'security': 'reality',
          'pbk': _realityKey,
          'sni': 's.example',
          'alpn': 'h3',
        }),
      );
      final tls = outbound['tls']! as Map<String, Object?>;

      expect(tls['utls'], isNotNull);
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

    test('a fingerprint never reaches a QUIC protocol', () {
      // The core answers a `utls` block over QUIC with "unsupported usage for
      // uTLS" on every connection; Clash configs set the fingerprint globally.
      for (final protocol in <Protocol>[Protocol.hysteria2, Protocol.tuic]) {
        final outbound = _build(
          _node(protocol, <String, Object?>{
            'password': 'pw',
            'uuid': 'u',
            'fp': 'chrome',
          }),
        );
        final tls = outbound['tls']! as Map<String, Object?>;

        expect(tls.containsKey('utls'), isFalse, reason: protocol.name);
      }
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
