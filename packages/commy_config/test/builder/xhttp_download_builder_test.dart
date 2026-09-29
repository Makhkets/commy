import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// A VLESS XHTTP node whose `extra` carries [route] as its downloadSettings.
ProxyNode _node(
  Map<String, Object?>? route, {
  String? mode,
  int port = 443,
  Map<String, Object?> params = const <String, Object?>{},
}) =>
    ProxyNode(
      id: 'n1',
      name: 'N',
      protocol: Protocol.vless,
      host: 'up.example',
      port: port,
      params: <String, Object?>{
        'uuid': 'u',
        'type': 'xhttp',
        'security': 'tls',
        'path': '/xh',
        if (mode != null) 'mode': mode,
        if (route != null)
          'extra': jsonEncode(<String, Object?>{
            'downloadSettings': route,
          }),
        ...params,
      },
    );

Map<String, Object?>? _download(ProxyNode node) {
  final outbound = OutboundBuilder.build(node: node, tag: 't');
  final transport = outbound['transport']! as Map<String, Object?>;
  return transport['download'] as Map<String, Object?>?;
}

Matcher _refused(String reason) => throwsA(
      isA<ConfigBuildException>().having(
        (error) => error.reason,
        'reason',
        allOf(contains('downloadSettings'), contains(reason)),
      ),
    );

Map<String, Object?> _route([Map<String, Object?> more = const {}]) =>
    <String, Object?>{
      'address': 'dl.example',
      'port': 8443,
      'network': 'xhttp',
      'security': 'tls',
      'xhttpSettings': <String, Object?>{'path': '/xh'},
      ...more,
    };

void main() {
  group('the download route', () {
    test('is its own server, TLS and path', () {
      expect(_download(_node(_route())), <String, Object?>{
        'server': 'dl.example',
        'server_port': 8443,
        'tls': <String, Object?>{
          'enabled': true,
          'server_name': 'dl.example',
        },
        'path': '/xh',
      });
    });

    test('is absent when there is none, or its address was left empty', () {
      expect(_download(_node(null)), isNull);
      expect(
        _download(_node(_route(<String, Object?>{'address': ''}))),
        isNull,
      );
      expect(
        _download(_node(_route(<String, Object?>{'address': null}))),
        isNull,
      );
      expect(
        _download(_node(<String, Object?>{'port': 443, 'network': 'xhttp'})),
        isNull,
      );
    });

    test('an empty address is no route even in stream-one', () {
      // What Xray's own template ships; nothing to conflict with.
      final route = _route(<String, Object?>{'address': ' '});

      expect(_download(_node(route, mode: 'stream-one')), isNull);
    });

    test('is ignored in stream-one, where there is no GET to send apart', () {
      // Xray refuses the pair; sing-box-extended ignores the route, and so
      // did Commy before it had one. A server that works stays working.
      final outbound = OutboundBuilder.build(
        node: _node(_route(), mode: 'stream-one'),
        tag: 't',
      );

      expect(outbound['transport'], <String, Object?>{
        'type': 'xhttp',
        'mode': 'stream-one',
        'path': '/xh',
      });
    });

    test('takes the main port when it names none, or zero', () {
      final noPort = Map<String, Object?>.of(_route())..remove('port');

      expect(_download(_node(noPort, port: 2053))!['server_port'], 2053);
      expect(
        _download(_node(_route(<String, Object?>{'port': 0}), port: 2053))![
            'server_port'],
        2053,
      );
      expect(
        _download(
          _node(_route(<String, Object?>{'port': '8080'})),
        )!['server_port'],
        8080,
      );
    });

    test('refuses a port that is not one', () {
      for (final port in <Object>[70000, -1, 'https']) {
        expect(
          () => _download(_node(_route(<String, Object?>{'port': port}))),
          _refused('port'),
          reason: '$port',
        );
      }
    });

    test('refuses an address that is not a server', () {
      for (final address in <String>['0.0.0.0', '::', 'a b', 'x/y']) {
        expect(
          () => _download(_node(_route(<String, Object?>{'address': address}))),
          _refused('address'),
          reason: address,
        );
      }
    });

    test('reads an IPv6 address written in brackets, and any case', () {
      final v6 = _download(
        _node(_route(<String, Object?>{'address': '[2001:DB8::1]'})),
      )!;
      final named = _download(
        _node(_route(<String, Object?>{'address': 'DL.Example'})),
      )!;

      expect(v6['server'], '2001:db8::1');
      // An address is not a name to send as SNI.
      expect((v6['tls']! as Map<String, Object?>)['server_name'], isNull);
      expect(named['server'], 'dl.example');
    });

    test('must be XHTTP, under either name, or left unsaid', () {
      final unsaid = Map<String, Object?>.of(_route())..remove('network');

      expect(_download(_node(unsaid)), isNotNull);
      expect(
        _download(_node(_route(<String, Object?>{'network': 'splithttp'}))),
        isNotNull,
      );
      expect(
        () => _download(_node(_route(<String, Object?>{'network': 'ws'}))),
        _refused('ws'),
      );
      expect(
        () => _download(
          _node(
            Map<String, Object?>.of(unsaid)..['method'] = 'grpc',
          ),
        ),
        _refused('grpc'),
      );
    });

    test('with no security is cleartext, whatever the main route is', () {
      final download = _download(
        _node(_route(<String, Object?>{'security': 'none'})),
      )!;

      expect(download.containsKey('tls'), isFalse);
    });

    test('refuses a security Xray does not have, not downgrade it', () {
      expect(
        () => _download(_node(_route(<String, Object?>{'security': 'tsl'}))),
        _refused('tsl'),
      );
      expect(
        _download(_node(_route(<String, Object?>{'security': 'xtls'})))!['tls'],
        isNotNull,
      );
    });

    test('with REALITY needs its key, and a short id that is one', () {
      Map<String, Object?> reality(Map<String, Object?> settings) =>
          _route(<String, Object?>{
            'security': 'reality',
            'realitySettings': <String, Object?>{
              'serverName': 'www.example.com',
              ...settings,
            },
          });

      expect(
        () => _download(_node(reality(const <String, Object?>{}))),
        _refused('public key'),
      );
      expect(
        () => _download(
          _node(
            reality(<String, Object?>{
              'publicKey': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
              'shortId': 'zz',
            }),
          ),
        ),
        _refused('short id'),
      );
      final built = _download(
        _node(
          reality(<String, Object?>{
            'password': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
            'shortId': 'ab',
          }),
        ),
      )!;
      final tls = built['tls']! as Map<String, Object?>;
      expect(tls['reality'], <String, Object?>{
        'enabled': true,
        'public_key': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
        'short_id': 'ab',
      });
      expect(
        (tls['utls']! as Map<String, Object?>)['fingerprint'],
        TlsOptionsBuilder.realityFingerprint,
      );
    });

    test('is secured by what `security` says, not by what else it carries', () {
      // A route copied from a REALITY config and switched to TLS for a CDN.
      final download = _download(
        _node(
          _route(<String, Object?>{
            'tlsSettings': <String, Object?>{'serverName': 'cdn.example'},
            'realitySettings': <String, Object?>{
              'publicKey': 'xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k',
              'serverName': 'www.example.com',
            },
          }),
        ),
      )!;

      expect(download['tls'], <String, Object?>{
        'enabled': true,
        'server_name': 'cdn.example',
      });
    });

    test('takes its host from its own settings, never from the main route', () {
      final ownHost = _download(
        _node(
          _route(<String, Object?>{
            'xhttpSettings': <String, Object?>{
              'path': '/xh',
              'host': 'cdn.example',
            },
          }),
          params: <String, Object?>{'host': 'main.example'},
        ),
      )!;
      final headerHost = _download(
        _node(
          _route(<String, Object?>{
            'xhttpSettings': <String, Object?>{
              'path': '/xh',
              'headers': <String, Object?>{'Host': 'front.example'},
            },
          }),
        ),
      )!;
      final noHost = _download(
        _node(_route(), params: <String, Object?>{'host': 'main.example'}),
      )!;

      expect(ownHost['host'], 'cdn.example');
      expect(headerHost['host'], 'front.example');
      expect(headerHost.containsKey('headers'), isFalse);
      expect(noHost.containsKey('host'), isFalse);
    });

    test('holds its own settings to the rules of its own mode', () {
      Map<String, Object?> dressed(Map<String, Object?> settings) =>
          _route(<String, Object?>{
            'xhttpSettings': <String, Object?>{'path': '/xh', ...settings},
          });

      expect(
        () => _download(_node(dressed(<String, Object?>{'mode': 'turbo'}))),
        _refused('turbo'),
      );
      expect(
        () => _download(
          _node(
            dressed(<String, Object?>{'uplinkDataPlacement': 'header'}),
            mode: 'packet-up',
          ),
        ),
        _refused('packet-up'),
      );
      // Its mode is used for nothing else: the core is not told it.
      expect(
        _download(
          _node(
            dressed(<String, Object?>{
              'mode': 'packet-up',
              'uplinkDataPlacement': 'header',
            }),
          ),
        ),
        isNot(contains('mode')),
      );
    });

    test('a route inside the route is never read, so never refused', () {
      // Xray parses it and never dials it; one that could not be built must
      // not cost the server its import.
      final extra = Uri.encodeQueryComponent(
        jsonEncode(<String, Object?>{
          'downloadSettings': _route(<String, Object?>{
            'xhttpSettings': <String, Object?>{
              'path': '/xh',
              'downloadSettings': <String, Object?>{
                'address': '0.0.0.0',
                'network': 'ws',
              },
            },
          }),
        }),
      );
      final node = CommyLinkParser()
          .parse(
              'vless://u@up.example:443?type=xhttp&security=tls&extra=$extra#x',)
          .valueOrNull!
          .nodes
          .single;

      expect(_download(node)!['server'], 'dl.example');
    });

    test('drops sockopt, and a route inside the route', () {
      final download = _download(
        _node(
          _route(<String, Object?>{
            'sockopt': <String, Object?>{'mark': 255, 'dialerProxy': 'x'},
            'xhttpSettings': <String, Object?>{
              'path': '/xh',
              'downloadSettings': <String, Object?>{
                'address': 'nested.example',
                'port': 1,
              },
            },
          }),
        ),
      )!;

      expect(download.keys, isNot(contains('download')));
      expect(jsonEncode(download), isNot(contains('nested')));
      expect(jsonEncode(download), isNot(contains('255')));
    });

    test('over HTTP/3 carries no uTLS', () {
      final download = _download(
        _node(
          _route(<String, Object?>{
            'tlsSettings': <String, Object?>{
              'alpn': 'h3',
              'fingerprint': 'chrome',
            },
          }),
        ),
      )!;

      expect(download['tls'], <String, Object?>{
        'enabled': true,
        'server_name': 'dl.example',
        'alpn': <String>['h3'],
      });
    });

    test('a bad route leaves only its own server out, and says why', () {
      final bad = _node(_route(<String, Object?>{'network': 'ws'})).copyWith(
        id: 'bad',
        name: 'Split',
      );
      const good = ProxyNode(
        id: 'good',
        name: 'Good',
        protocol: Protocol.vless,
        host: 'g.example',
        port: 443,
        params: <String, Object?>{'uuid': 'u'},
      );

      final built = const SingBoxConfigBuilder()
          .build(
            SingBoxBuildRequest(
              nodes: <ProxyNode>[bad, good],
              selectedNodeId: 'good',
              routing: RoutingPolicy.defaults,
              dns: DnsSettings.defaults,
              settings: AppSettings.defaults,
              platform: ConfigPlatform.android,
            ),
          )
          .valueOrNull!;

      expect(built.leftOut.map((node) => node.nodeId), <String>['bad']);
      expect(
        '${built.leftOut.single}',
        allOf(contains('Split'), contains('downloadSettings')),
      );
    });
  });
}
