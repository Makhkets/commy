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
              'endpoint':
                  buildFrom(link)['type'] == Protocol.wireguard.wireName,
              'object': buildFrom(link),
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

  test('the fixture holds every link below, and nothing else', () {
    expect(
      <String>[for (final entry in cases) '${entry['link']}'],
      <String>[for (final (_, link) in _links) link],
    );
  });

  for (final entry in cases) {
    test('the core is handed what the fixture promises: ${entry['name']}', () {
      expect(buildFrom('${entry['link']}'), entry['object']);
    });
  }
}

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
