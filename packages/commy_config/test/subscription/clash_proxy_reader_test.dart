import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ClashProxyReader', () {
    test('reads a vless Reality entry', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'NL Reality',
        'type': 'vless',
        'server': 'nl.example.com',
        'port': 443,
        'uuid': 'the-uuid',
        'flow': 'xtls-rprx-vision',
        'tls': true,
        'servername': 'www.microsoft.com',
        'client-fingerprint': 'chrome',
        'reality-opts': <String, Object?>{
          'public-key': 'PUBKEY',
          'short-id': 'ab12',
        },
        'network': 'tcp',
      });

      expect(node.protocol, Protocol.vless);
      expect(node.name, 'NL Reality');
      expect(node.host, 'nl.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.security), 'reality');
      expect(node.param(ParamKeys.publicKey), 'PUBKEY');
      expect(node.param(ParamKeys.shortId), 'ab12');
      expect(node.param(ParamKeys.fingerprint), 'chrome');
      expect(node.param(ParamKeys.sni), 'www.microsoft.com');
      expect(node.param(ParamKeys.flow), 'xtls-rprx-vision');
    });

    test('reads a vmess websocket entry with its host header', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'WS',
        'type': 'vmess',
        'server': 'ws.example.com',
        'port': 443,
        'uuid': 'the-uuid',
        'alterId': 0,
        'cipher': 'auto',
        'tls': true,
        'network': 'ws',
        'ws-opts': <String, Object?>{
          'path': '/ray',
          'headers': <String, Object?>{'Host': 'cdn.example.com'},
        },
      });

      expect(node.protocol, Protocol.vmess);
      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/ray');
      expect(node.param(ParamKeys.host), 'cdn.example.com');
      expect(node.param(ParamKeys.security), 'tls');
    });

    test('reads a grpc service name', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'G',
        'type': 'trojan',
        'server': 'g.example.com',
        'port': 443,
        'password': 'pw',
        'network': 'grpc',
        'grpc-opts': <String, Object?>{'grpc-service-name': 'svc'},
      });

      expect(node.param(ParamKeys.serviceName), 'svc');
      expect(node.param(ParamKeys.security), 'tls');
    });

    test('turns a clash obfs plugin into the SIP003 spelling', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'SS',
        'type': 'ss',
        'server': 'ss.example.com',
        'port': 8388,
        'cipher': 'aes-256-gcm',
        'password': 'pw',
        'plugin': 'obfs',
        'plugin-opts': <String, Object?>{
          'mode': 'tls',
          'host': 'bing.com',
        },
      });

      expect(node.param(ParamKeys.plugin), 'obfs-local');
      expect(node.param(ParamKeys.pluginOpts), 'obfs=tls;obfs-host=bing.com');
    });

    test('reads a hysteria2 entry', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'HY',
        'type': 'hysteria2',
        'server': 'hy.example.com',
        'port': 8443,
        'password': 'pw',
        'sni': 'hy.example.com',
        'obfs': 'salamander',
        'obfs-password': 'o',
        'skip-cert-verify': true,
        'up': 100,
        'down': 500,
      });

      expect(node.protocol, Protocol.hysteria2);
      expect(node.param(ParamKeys.obfs), 'salamander');
      expect(node.param(ParamKeys.obfsPassword), 'o');
      expect(node.params[ParamKeys.allowInsecure], isTrue);
      expect(node.params[ParamKeys.upMbps], 100);
    });

    test('reads a wireguard entry and adds the missing masks', () {
      final node = ClashProxyReader.read(<String, Object?>{
        'name': 'WG',
        'type': 'wireguard',
        'server': 'wg.example.com',
        'port': 51820,
        'private-key': 'PK',
        'public-key': 'PEER',
        'ip': '10.0.0.2',
        'ipv6': 'fd00::2',
        'mtu': 1420,
        'reserved': <int>[0, 0, 0],
      });

      expect(node.protocol, Protocol.wireguard);
      expect(node.param(ParamKeys.localAddress), '10.0.0.2/32,fd00::2/128');
      expect(node.param(ParamKeys.reserved), '0,0,0');
      expect(node.params[ParamKeys.mtu], 1420);
    });

    test('names an unsupported clash type instead of guessing', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'old',
          'type': 'ssr',
          'server': 'a.example',
          'port': 443,
        }),
        throwsA(
          isA<LinkFormatException>().having(
            (error) => error.reason,
            'reason',
            contains('ssr'),
          ),
        ),
      );
    });

    test('rejects an entry with no port', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'uuid': 'u',
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a transport the core cannot carry', () {
      expect(
        () => ClashProxyReader.read(<String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'port': 443,
          'uuid': 'u',
          'network': 'kcp',
        }),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('ClashProxyReader xhttp', () {
    Map<String, Object?> proxy(Map<String, Object?> options) =>
        <String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'port': 443,
          'uuid': 'u',
          'tls': true,
          'servername': 's.example',
          'network': 'xhttp',
          'xhttp-opts': options,
        };

    test('reads host, path and mode', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'host': 'cdn.example',
          'mode': 'stream-up',
        }),
      );

      expect(node.param('type'), 'xhttp');
      expect(node.param('path'), '/xh');
      expect(node.param('host'), 'cdn.example');
      expect(node.param('mode'), 'stream-up');
      expect(node.param('extra'), isNull);
    });

    test('turns the kebab-case settings into the extra a link would carry', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'mode': 'packet-up',
          'no-grpc-header': true,
          'x-padding-bytes': '100-500',
          'sc-max-each-post-bytes': 800000,
          'headers': <String, Object?>{'X-Forwarded-For': '1.2.3.4'},
          'reuse-settings': <String, Object?>{
            'max-concurrency': '16-32',
            'max-connections': '0',
            'h-keep-alive-period': 0,
          },
        }),
      );
      final outbound = OutboundBuilder.build(node: node, tag: 't');

      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'mode': 'packet-up',
        'path': '/xh',
        'headers': <String, String>{'X-Forwarded-For': '1.2.3.4'},
        'x_padding_bytes': '100-500',
        'no_grpc_header': true,
        'sc_max_each_post_bytes': 800000,
        'xmux': <String, Object?>{'max_concurrency': '16-32'},
      });
    });

    test('a download route inherits from the proxy what it leaves unsaid', () {
      // mihomo fills every field the block does not set from the proxy.
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/up',
          'mode': 'packet-up',
          'x-padding-bytes': '200-400',
          'download-settings': <String, Object?>{'path': '/down'},
        })
          ..['client-fingerprint'] = 'firefox',
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport['download'], <String, Object?>{
        'server': 'a.example',
        'server_port': 443,
        'tls': <String, Object?>{
          'enabled': true,
          'server_name': 's.example',
          'utls': <String, Object?>{'enabled': true, 'fingerprint': 'firefox'},
        },
        // Under TLS the same name the core would fall back to.
        'host': 's.example',
        'path': '/down',
        'x_padding_bytes': '200-400',
      });
    });

    test('a download route replaces what it sets, REALITY included', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'host': 'up-front.example',
          'download-settings': <String, Object?>{
            'server': '203.0.113.9',
            'port': 8443,
            'servername': 'www.example.com',
            'reality-opts': <String, Object?>{
              'public-key': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
              'short-id': 'cd34',
            },
            'host': 'dl-front.example',
            'headers': <String, Object?>{'X-Edge': '1'},
            'reuse-settings': <String, Object?>{'max-connections': '1'},
          },
        }),
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;
      final download = transport['download']! as Map<String, Object?>;

      expect(download['server'], '203.0.113.9');
      expect(download['server_port'], 8443);
      expect(download['host'], 'dl-front.example');
      expect(download['headers'], <String, String>{'X-Edge': '1'});
      expect(download['xmux'], <String, Object?>{'max_connections': 1});
      final tls = download['tls']! as Map<String, Object?>;
      expect(tls['server_name'], 'www.example.com');
      expect(tls['reality'], <String, Object?>{
        'enabled': true,
        'public_key': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
        'short_id': 'cd34',
      });
      // The main route keeps its own.
      expect(transport['host'], 'up-front.example');
      expect(transport.containsKey('headers'), isFalse);
    });

    test('a download route without TLS still names the server as its host', () {
      // mihomo: the route's host, else the proxy's, else the server name.
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'download-settings': <String, Object?>{
            'server': '104.16.1.1',
            'port': 80,
            'tls': false,
          },
        }),
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport['download'], <String, Object?>{
        'server': '104.16.1.1',
        'server_port': 80,
        'host': 's.example',
        'path': '/xh',
      });
    });

    test('a download route replaces the TLS details it sets', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'download-settings': <String, Object?>{
            'skip-cert-verify': true,
            'alpn': <String>['http/1.1'],
            'client-fingerprint': 'safari',
          },
        })
          ..['alpn'] = <String>['h2']
          ..['client-fingerprint'] = 'firefox'
          ..['skip-cert-verify'] = false,
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;
      final tls = (transport['download']! as Map<String, Object?>)['tls']!
          as Map<String, Object?>;

      expect(tls['insecure'], isTrue);
      expect(tls['alpn'], <String>['http/1.1']);
      expect(tls['utls'], <String, Object?>{
        'enabled': true,
        'fingerprint': 'safari',
      });
    });

    test('a Host among the xhttp-opts headers is the host', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'headers': <String, Object?>{'Host': 'front.example'},
        }),
      );

      expect(node.param('host'), 'front.example');
    });

    test('a certificate pin is not a uTLS fingerprint', () {
      // In mihomo `fingerprint` pins the server certificate;
      // `client-fingerprint` is the hello.
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{'path': '/xh'})
          ..['fingerprint'] = 'aa11bb22cc33dd44ee55ff66aa11bb22cc33dd44',
      );

      expect(node.param('fp'), isNull);
    });

    test('a download route is stored as Xray spells it', () {
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'path': '/xh',
          'download-settings': <String, Object?>{'server': 'cdn.example'},
        }),
      );
      final extra = jsonDecode(node.param('extra')!) as Map<String, Object?>;
      final route = extra['downloadSettings']! as Map<String, Object?>;

      expect(route['address'], 'cdn.example');
      expect(route['port'], 443);
      expect(route['network'], 'xhttp');
      expect(route['security'], 'tls');
      expect(route.containsKey('server'), isFalse);
    });

    test('ignores a download route in stream-one', () {
      // mihomo refuses the pair; a server that connects is kept instead.
      final node = ClashProxyReader.read(
        proxy(<String, Object?>{
          'mode': 'stream-one',
          'download-settings': <String, Object?>{'server': 'cdn.example'},
        }),
      );
      final transport =
          OutboundBuilder.build(node: node, tag: 't')['transport']!
              as Map<String, Object?>;

      expect(transport.containsKey('download'), isFalse);
    });

    test('works with no xhttp-opts at all', () {
      final node = ClashProxyReader.read(
        <String, Object?>{
          'name': 'x',
          'type': 'vless',
          'server': 'a.example',
          'port': 443,
          'uuid': 'u',
          'network': 'xhttp',
        },
      );

      expect(node.param('type'), 'xhttp');
    });

    test('rejects a mode that does not exist', () {
      expect(
        () => ClashProxyReader.read(proxy(<String, Object?>{'mode': 'turbo'})),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
