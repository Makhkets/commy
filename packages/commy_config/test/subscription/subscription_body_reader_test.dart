import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _plainList = '''
vless://uuid@nl.example.com:443?security=tls&sni=nl.example.com#NL
trojan://pw@de.example.com:443#DE
hysteria2://pw@fi.example.com:8443#FI
''';

const _clashDocument = '''
port: 7890
mode: rule
proxies:
  - name: "NL Reality"
    type: vless
    server: nl.example.com
    port: 443
    uuid: the-uuid
    flow: xtls-rprx-vision
    tls: true
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: PUBKEY
      short-id: ab12
    network: tcp
  - name: "DE WS"
    type: trojan
    server: de.example.com
    port: 443
    password: pw
    network: ws
    ws-opts: { path: /ray, headers: { Host: cdn.example.com } }
  - name: "broken"
    type: ssr
    server: old.example.com
    port: 443
proxy-groups:
  - name: PROXY
    type: select
    proxies: [ "NL Reality", "DE WS" ]
''';

void main() {
  final reader = SubscriptionBodyReader();

  group('SubscriptionBodyReader format detection', () {
    test('reads a plain list of links', () {
      final outcome = reader.read(_plainList);

      expect(outcome.nodes, hasLength(3));
      expect(
        outcome.nodes.map((node) => node.name),
        <String>['NL', 'DE', 'FI'],
      );
      expect(outcome.failures, isEmpty);
    });

    test('reads the same list wrapped in standard base64', () {
      final outcome = reader.read(LenientBase64.encode(_plainList));

      expect(outcome.nodes, hasLength(3));
    });

    test('reads the same list wrapped in url-safe base64 without padding', () {
      final outcome = reader.read(LenientBase64.encodeUrlSafe(_plainList));

      expect(outcome.nodes, hasLength(3));
    });

    test('reads base64 broken across lines', () {
      final wrapped = LenientBase64.encode(_plainList)
          .replaceAllMapped(RegExp('.{60}'), (match) => '${match[0]}\n');
      final outcome = reader.read(wrapped);

      expect(outcome.nodes, hasLength(3));
    });

    test('unwraps base64 nested twice', () {
      final outcome = reader.read(
        LenientBase64.encode(LenientBase64.encode(_plainList)),
      );

      expect(outcome.nodes, hasLength(3));
    });

    test('reads a Clash document and explains the entry it dropped', () {
      final outcome = reader.read(_clashDocument);

      expect(outcome.nodes, hasLength(2));
      expect(outcome.nodes.first.name, 'NL Reality');
      expect(outcome.nodes.first.param(ParamKeys.publicKey), 'PUBKEY');
      expect(outcome.nodes.last.param(ParamKeys.path), '/ray');
      expect(outcome.failures, hasLength(1));
      expect(outcome.failures.single.reason, contains('ssr'));
    });

    test('reads a sing-box configuration through its outbounds', () {
      final document = jsonEncode(<String, Object?>{
        'outbounds': <Map<String, Object?>>[
          <String, Object?>{
            'type': 'vless',
            'tag': 'NL',
            'server': 'nl.example.com',
            'server_port': 443,
            'uuid': 'the-uuid',
          },
          <String, Object?>{'type': 'direct', 'tag': 'direct'},
          <String, Object?>{
            'type': 'selector',
            'tag': 'proxy',
            'outbounds': <String>['NL'],
          },
        ],
      });
      final outcome = reader.read(document);

      expect(outcome.nodes, hasLength(1));
      expect(outcome.nodes.single.name, 'NL');
    });

    test('reads a bare JSON array of node objects', () {
      final document = jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'type': 'trojan',
          'tag': 'One',
          'server': 'a.example',
          'server_port': 443,
          'password': 'pw',
        },
      ]);
      final outcome = reader.read(document);

      expect(outcome.nodes, hasLength(1));
      expect(outcome.nodes.single.protocol, Protocol.trojan);
    });

    test('reads a JSON array that holds plain links', () {
      final outcome = reader.read(
        jsonEncode(<String>['vless://uuid@a.example:443#One']),
      );

      expect(outcome.nodes, hasLength(1));
      expect(outcome.nodes.single.name, 'One');
    });

    test('reads a Clash document rendered as JSON', () {
      final document = jsonEncode(<String, Object?>{
        'proxies': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'SS',
            'type': 'ss',
            'server': 'ss.example.com',
            'port': 8388,
            'cipher': 'aes-256-gcm',
            'password': 'pw',
          },
        ],
      });
      final outcome = reader.read(document);

      expect(outcome.nodes.single.protocol, Protocol.shadowsocks);
    });
  });

  group('SubscriptionBodyReader edges', () {
    test('an empty body is a failure, not a crash', () {
      final outcome = reader.read('   ');

      expect(outcome.nodes, isEmpty);
      expect(outcome.failures.single.reason, 'The body is empty');
    });

    test('an unrecognisable body says so', () {
      final outcome = reader.read('the quick brown fox');

      expect(outcome.nodes, isEmpty);
      expect(outcome.failures, isNotEmpty);
    });

    test('a partly broken list still imports the good half', () {
      final outcome = reader.read(
        'vless://uuid@a.example:443#Good\n'
        'vless://@b.example:443#Bad\n',
      );

      expect(outcome.nodes, hasLength(1));
      expect(outcome.failures, hasLength(1));
    });

    test('stamps the subscription id and keeps the panel order', () {
      final outcome = reader.read(
        _plainList,
        subscriptionId: 'sub-9',
        startIndex: 10,
      );

      expect(
        outcome.nodes.every((node) => node.subscriptionId == 'sub-9'),
        isTrue,
      );
      expect(outcome.nodes.map((node) => node.sortIndex), <int>[10, 11, 12]);
    });

    test('canRead recognises every supported shape', () {
      expect(reader.canRead(_plainList), isTrue);
      expect(reader.canRead(LenientBase64.encode(_plainList)), isTrue);
      expect(reader.canRead(_clashDocument), isTrue);
      expect(reader.canRead('{"outbounds": []}'), isTrue);
      expect(reader.canRead('the quick brown fox'), isFalse);
      expect(reader.canRead(''), isFalse);
    });
  });
}
