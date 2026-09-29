import 'dart:convert';

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

    test('reads a REALITY key under its newer name, and a Host header', () {
      final outbound = xray(
        <String, Object?>{
          'path': '/xh',
          'headers': <String, Object?>{'Host': 'front.example', 'X-A': '1'},
        },
        'xhttpSettings',
      );
      (outbound['streamSettings']! as Map<String, Object?>)
        ..remove('tlsSettings')
        ..['security'] = 'reality'
        ..['realitySettings'] = <String, Object?>{
          'serverName': 'www.example.com',
          'password': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
          'shortId': 'ab12',
        };

      final node = SingBoxOutboundReader.read(outbound);
      final built = OutboundBuilder.build(node: node, tag: 't');

      expect(
        node.param(ParamKeys.publicKey),
        'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
      );
      expect(node.param(ParamKeys.host), 'front.example');
      expect(
        ((built['tls']! as Map<String, Object?>)['reality']!
            as Map<String, Object?>)['public_key'],
        'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
      );
      expect(built['transport'], <String, Object?>{
        'type': 'xhttp',
        'host': 'front.example',
        'path': '/xh',
        'headers': <String, String>{'X-A': '1'},
      });
    });

    test('reads an Xray download route and hands it to the core', () {
      final node = SingBoxOutboundReader.read(
        xray(
          <String, Object?>{
            'path': '/xh',
            'extra': <String, Object?>{
              'downloadSettings': <String, Object?>{
                'address': 'cdn.example',
                'port': 443,
                'network': 'xhttp',
                'security': 'tls',
                'xhttpSettings': <String, Object?>{'path': '/xh'},
              },
            },
          },
          'xhttpSettings',
        ),
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport['download'], <String, Object?>{
        'server': 'cdn.example',
        'server_port': 443,
        'tls': <String, Object?>{
          'enabled': true,
          'server_name': 'cdn.example',
        },
        'path': '/xh',
      });
    });

    test('refuses an Xray download route the core could never dial', () {
      expect(
        () => SingBoxOutboundReader.read(
          xray(
            <String, Object?>{
              'path': '/xh',
              'downloadSettings': <String, Object?>{
                'address': '0.0.0.0',
                'port': 443,
              },
            },
            'xhttpSettings',
          ),
        ),
        throwsA(
          isA<LinkFormatException>().having(
            (error) => error.reason,
            'reason',
            contains('downloadSettings'),
          ),
        ),
      );
    });

    test('keeps a stream-one sing-box outbound with a download route', () {
      // sing-box-extended ignores the route in stream-one.
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'up.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'tls': <String, Object?>{'enabled': true},
        'transport': <String, Object?>{
          'type': 'xhttp',
          'mode': 'stream-one',
          'path': '/x',
          'download': <String, Object?>{
            'server': 'cdn.example',
            'server_port': 443,
            'tls': <String, Object?>{'enabled': true},
            'path': '/x',
          },
        },
      });
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport.containsKey('download'), isFalse);
    });

    test('reads back the download route our own builder writes', () {
      const download = <String, Object?>{
        'server': 'cdn.example',
        'server_port': 8443,
        'tls': <String, Object?>{
          'enabled': true,
          'server_name': 'a.example',
          'alpn': <String>['h2'],
          'utls': <String, Object?>{'enabled': true, 'fingerprint': 'firefox'},
        },
        'host': 'c.example',
        'path': '/down',
        'headers': <String, String>{'X-Edge': '1'},
        'x_padding_bytes': '200-400',
        'session_placement': 'query',
        'xmux': <String, Object?>{'max_connections': 2},
      };
      final transport = <String, Object?>{
        'type': 'xhttp',
        'mode': 'packet-up',
        'path': '/up',
        'download': download,
      };
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'tls': <String, Object?>{'enabled': true, 'server_name': 's.example'},
        'transport': transport,
      });

      // Stored as Xray spells it, so a link made from the node is one Xray
      // reads.
      final extra =
          jsonDecode(node.param(ParamKeys.extra)!) as Map<String, Object?>;
      final route = extra['downloadSettings']! as Map<String, Object?>;
      expect(route['address'], 'cdn.example');
      expect(route['port'], 8443);
      expect(route['security'], 'tls');
      expect(route.containsKey('server'), isFalse);
      // And built back into the block it came from.
      expect(
        OutboundBuilder.build(node: node, tag: 't')['transport'],
        transport,
      );
    });

    test('a download route that sends no SNI keeps sending none', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'transport': <String, Object?>{
          'type': 'xhttp',
          'download': <String, Object?>{
            'server': 'dl.example',
            'server_port': 443,
            'tls': <String, Object?>{'enabled': true, 'disable_sni': true},
          },
        },
      });
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;
      final download = transport['download']! as Map<String, Object?>;

      expect(
        (download['tls']! as Map<String, Object?>)['disable_sni'],
        isTrue,
      );
    });

    test('holds a sing-box download route to the main mode', () {
      // The fork's route has no mode and repeats the main settings, the
      // upload-only ones included; it is checked against the main mode.
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'transport': <String, Object?>{
          'type': 'xhttp',
          'mode': 'packet-up',
          'uplink_http_method': 'GET',
          'download': <String, Object?>{
            'server': 'dl.example',
            'server_port': 443,
            'path': '/xh',
            'uplink_http_method': 'GET',
          },
        },
      });
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport['download'], <String, Object?>{
        'server': 'dl.example',
        'server_port': 443,
        'path': '/xh',
      });
    });

    test('drops a sing-box download route that names no server', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'transport': <String, Object?>{
          'type': 'xhttp',
          'download': <String, Object?>{'path': '/down'},
        },
      });

      expect(node.param(ParamKeys.extra), isNull);
    });

    test('reads the transport under its newer key, which wins', () {
      Map<String, Object?> outbound(Map<String, Object?> keys) {
        final value = xray(<String, Object?>{'path': '/m'}, 'xhttpSettings');
        (value['streamSettings']! as Map<String, Object?>)
          ..remove('network')
          ..addAll(keys);
        return value;
      }

      final alone = SingBoxOutboundReader.read(
        outbound(<String, Object?>{'method': 'xhttp'}),
      );
      final both = SingBoxOutboundReader.read(
        outbound(<String, Object?>{'network': 'tcp', 'method': 'xhttp'}),
      );

      expect(alone.param(ParamKeys.transport), 'xhttp');
      expect(both.param(ParamKeys.transport), 'xhttp');
    });

    test('keeps the insecure flag and a Host header of a sing-box route', () {
      final node = SingBoxOutboundReader.read(<String, Object?>{
        'type': 'vless',
        'tag': 'x',
        'server': 'a.example',
        'server_port': 443,
        'uuid': 'the-uuid',
        'transport': <String, Object?>{
          'type': 'xhttp',
          'download': <String, Object?>{
            'server': 'dl.example',
            'server_port': 443,
            'tls': <String, Object?>{'enabled': true, 'insecure': true},
            'headers': <String, Object?>{'Host': 'front.example'},
          },
        },
      });
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;
      final download = transport['download']! as Map<String, Object?>;

      expect((download['tls']! as Map<String, Object?>)['insecure'], isTrue);
      expect(download['host'], 'front.example');
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

    test('reads the http header of a tcp stream', () {
      Map<String, Object?> outbound(String security) => <String, Object?>{
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': <String, Object?>{
              'vnext': <Map<String, Object?>>[
                <String, Object?>{
                  'address': 'xray.example.com',
                  'port': 80,
                  'users': <Map<String, Object?>>[
                    <String, Object?>{'id': 'the-uuid', 'encryption': 'none'},
                  ],
                },
              ],
            },
            'streamSettings': <String, Object?>{
              'network': 'raw',
              'security': security,
              'rawSettings': <String, Object?>{
                'header': <String, Object?>{
                  'type': 'http',
                  'request': <String, Object?>{
                    'path': <String>['/a', '/b'],
                    'headers': <String, Object?>{
                      'Host': <String>['b.example'],
                    },
                  },
                },
              },
            },
          };

      final node = SingBoxOutboundReader.read(outbound('none'));

      expect(node.param(ParamKeys.headerType), 'http');
      expect(
        OutboundBuilder.build(node: node, tag: 'proxy-out')['transport'],
        <String, Object?>{
          'type': 'http',
          'host': <String>['b.example'],
          'path': '/a',
          'method': 'GET',
        },
      );
      expect(
        () => SingBoxOutboundReader.read(outbound('tls')),
        throwsA(isA<LinkFormatException>()),
      );
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
