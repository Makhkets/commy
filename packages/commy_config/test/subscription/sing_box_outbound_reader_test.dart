import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('SingBoxOutboundReader (native)', () {
    test('reads a vless Reality outbound', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'proxy',
        'server': 'nl.example.com',
        'server_port': 443,
        'uuid': 'the-uuid',
        'flow': 'xtls-rprx-vision',
        'tls': <String, Object?>{
          'enabled': true,
          'server_name': 'www.microsoft.com',
          'utls': <String, Object?>{'enabled': true, 'fingerprint': 'chrome'},
          'reality': <String, Object?>{
            'enabled': true,
            'public_key': 'PUBKEY',
            'short_id': 'ab12',
          },
        },
      });

      expect(node.protocol, Protocol.vless);
      expect(node.name, 'proxy');
      expect(node.host, 'nl.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.security), 'reality');
      expect(node.param(ParamKeys.publicKey), 'PUBKEY');
      expect(node.param(ParamKeys.shortId), 'ab12');
      expect(node.param(ParamKeys.fingerprint), 'chrome');
    });

    test('reads a websocket transport with its host header', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'trojan',
        'tag': 'ws',
        'server': 'a.example',
        'server_port': 443,
        'password': 'pw',
        'transport': <String, Object?>{
          'type': 'ws',
          'path': '/ray',
          'headers': <String, Object?>{'Host': 'cdn.example'},
        },
      });

      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/ray');
      expect(node.param(ParamKeys.host), 'cdn.example');
    });

    test('reads a wireguard endpoint through its first peer', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'wireguard',
        'tag': 'wg',
        'address': <String>['10.0.0.2/32'],
        'private_key': 'PK',
        'mtu': 1420,
        'peers': <Map<String, Object?>>[
          <String, Object?>{
            'address': 'wg.example.com',
            'port': 51820,
            'public_key': 'PEER',
          },
        ],
      });

      expect(node.protocol, Protocol.wireguard);
      expect(node.host, 'wg.example.com');
      expect(node.port, 51820);
      expect(node.param(ParamKeys.privateKey), 'PK');
      expect(node.param(ParamKeys.peerPublicKey), 'PEER');
      expect(node.param(ParamKeys.localAddress), '10.0.0.2/32');
    });

    test('refuses plumbing outbounds', () {
      expect(
        SingBoxOutboundReader.looksLikeServer(<String, Object?>{
          'type': 'direct',
          'tag': 'direct',
        }),
        isFalse,
      );
      expect(
        SingBoxOutboundReader.looksLikeServer(<String, Object?>{
          'type': 'selector',
          'tag': 'proxy',
        }),
        isFalse,
      );
      expect(
        () => SingBoxOutboundReader.read(<String, Object?>{'type': 'block'}),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('SingBoxOutboundReader xhttp', () {
    test('reads back the block our own builder writes', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'tls': <String, Object?>{'enabled': true, 'server_name': 's.example'},
        'transport': <String, Object?>{
          'type': 'xhttp',
          'mode': 'packet-up',
          'host': 'cdn.example',
          'path': '/xh',
          'x_padding_bytes': '200-400',
          'no_grpc_header': true,
          'xmux': <String, Object?>{'max_concurrency': '16-32'},
        },
      });
      final outbound = OutboundBuilder.build(node: node, tag: 't');

      expect(node.param(ParamKeys.transport), 'xhttp');
      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'mode': 'packet-up',
        'host': 'cdn.example',
        'path': '/xh',
        'x_padding_bytes': '200-400',
        'no_grpc_header': true,
        'xmux': <String, Object?>{'max_concurrency': '16-32'},
      });
    });

    Map<String, Object?> xray(Map<String, Object?> settings, String key) =>
        <String, Object?>{
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': <String, Object?>{
            'vnext': <Map<String, Object?>>[
              <String, Object?>{
                'address': 'xray.example.com',
                'port': 443,
                'users': <Map<String, Object?>>[
                  <String, Object?>{'id': 'the-uuid', 'encryption': 'none'},
                ],
              },
            ],
          },
          'streamSettings': <String, Object?>{
            'network': 'xhttp',
            'security': 'tls',
            'tlsSettings': <String, Object?>{'serverName': 's.example'},
            key: settings,
          },
        };

    test('reads an Xray outbound whose settings sit beside host and path', () {
      final node = SingBoxOutboundReader.read(
        xray(
          <String, Object?>{
            'host': 'cdn.example',
            'path': '/xh',
            'mode': 'stream-up',
            'noGRPCHeader': true,
            'xmux': <String, Object?>{'maxConcurrency': '16-32'},
          },
          'xhttpSettings',
        ),
      );
      final outbound = OutboundBuilder.build(node: node, tag: 't');

      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'mode': 'stream-up',
        'host': 'cdn.example',
        'path': '/xh',
        'no_grpc_header': true,
        'xmux': <String, Object?>{'max_concurrency': '16-32'},
      });
    });

    test('lets `extra` replace them wholesale, as Xray does', () {
      final node = SingBoxOutboundReader.read(
        xray(
          <String, Object?>{
            'path': '/xh',
            'noGRPCHeader': true,
            'extra': <String, Object?>{'xPaddingBytes': '5-9'},
          },
          'xhttpSettings',
        ),
      );
      final outbound = OutboundBuilder.build(node: node, tag: 't');

      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'path': '/xh',
        'x_padding_bytes': '5-9',
      });
    });

    test('reads the settings under their first name too', () {
      final node = SingBoxOutboundReader.read(
        xray(<String, Object?>{'path': '/old'}, 'splithttpSettings'),
      );

      expect(node.param(ParamKeys.transport), 'xhttp');
      expect(node.param(ParamKeys.path), '/old');
    });
  });

  group('SingBoxOutboundReader (Xray)', () {
    test('reads a vless outbound out of vnext', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'tag': 'proxy',
        'protocol': 'vless',
        'settings': <String, Object?>{
          'vnext': <Map<String, Object?>>[
            <String, Object?>{
              'address': 'xray.example.com',
              'port': 443,
              'users': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'the-uuid',
                  'flow': 'xtls-rprx-vision',
                  'encryption': 'none',
                },
              ],
            },
          ],
        },
        'streamSettings': <String, Object?>{
          'network': 'tcp',
          'security': 'reality',
          'realitySettings': <String, Object?>{
            'publicKey': 'PUBKEY',
            'shortId': 'ab12',
            'serverName': 'www.microsoft.com',
            'fingerprint': 'chrome',
            'spiderX': '/',
          },
        },
      });

      expect(node.protocol, Protocol.vless);
      expect(node.host, 'xray.example.com');
      expect(node.param(ParamKeys.uuid), 'the-uuid');
      expect(node.param(ParamKeys.security), 'reality');
      expect(node.param(ParamKeys.publicKey), 'PUBKEY');
      expect(node.param(ParamKeys.spiderX), '/');
    });

    test('reads a trojan outbound out of servers', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'tag': 'tr',
        'protocol': 'trojan',
        'settings': <String, Object?>{
          'servers': <Map<String, Object?>>[
            <String, Object?>{
              'address': 'tr.example.com',
              'port': 443,
              'password': 'pw',
            },
          ],
        },
        'streamSettings': <String, Object?>{
          'network': 'ws',
          'security': 'tls',
          'tlsSettings': <String, Object?>{'serverName': 's.example'},
          'wsSettings': <String, Object?>{
            'path': '/x',
            'headers': <String, Object?>{'Host': 'h.example'},
          },
        },
      });

      expect(node.protocol, Protocol.trojan);
      expect(node.param(ParamKeys.password), 'pw');
      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/x');
      expect(node.param(ParamKeys.host), 'h.example');
      expect(node.param(ParamKeys.sni), 's.example');
    });

    test('rejects an Xray protocol we do not carry', () {
      expect(
        () => SingBoxOutboundReader.read(<String, Object?>{
          'protocol': 'vmess-legacy',
          'settings': <String, Object?>{},
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects an outbound with neither vnext nor servers', () {
      expect(
        () => SingBoxOutboundReader.read(<String, Object?>{
          'protocol': 'vless',
          'settings': <String, Object?>{},
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
