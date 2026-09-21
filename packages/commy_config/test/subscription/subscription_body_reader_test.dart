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

  group('SubscriptionBodyReader with XHTTP servers', () {
    // What a Remnawave panel serves for a host whose inbound is XHTTP: a
    // base64 list, empty `host=` and `headerType=`, and an `extra` that mixes
    // what a client reads with what only the server does. Every one of these
    // was refused until the core learned the transport.
    const extra = '{"xmux":{"maxConcurrency":"16-32","hMaxRequestTimes":'
        '"600-900","hMaxReusableSecs":"1800-3000"},"headers":{},'
        '"noGRPCHeader":false,"xPaddingBytes":"100-1000",'
        '"scMaxEachPostBytes":1000000,"scMinPostsIntervalMs":30,'
        '"scStreamUpServerSecs":"20-80","noSSEHeader":false}';
    final realityOverXhttp =
        'vless://11111111-2222-3333-4444-555555555555@nl.example.com:443'
        '?security=reality&type=xhttp&headerType=&path=%2Fapi%2Fv2&host='
        '&mode=auto&extra=${Uri.encodeComponent(extra)}'
        '&sni=www.example.org&fp=chrome&pbk=PUBKEY&sid=ab12'
        '#%F0%9F%87%B3%F0%9F%87%B1%20NL%20XHTTP';
    const behindCdn =
        'vless://11111111-2222-3333-4444-555555555555@cdn.example.com:443'
        '?security=tls&type=xhttp&path=%2Fcdn&host=front.example.com'
        '&mode=packet-up&alpn=h2&sni=front.example.com&fp=chrome#CDN';
    const vision =
        'vless://11111111-2222-3333-4444-555555555555@de.example.com:443'
        '?security=reality&type=tcp&flow=xtls-rprx-vision&sni=www.example.org'
        '&fp=chrome&pbk=PUBKEY&sid=ab12#DE%20Vision';
    final list = <String>[realityOverXhttp, behindCdn, vision].join('\n');

    test('imports every entry of a base64 list, XHTTP ones included', () {
      final outcome =
          SubscriptionBodyReader().read(base64.encode(utf8.encode(list)));

      expect(outcome.failures, isEmpty);
      expect(outcome.nodes, hasLength(3));
      expect(
        outcome.nodes.map((node) => node.param(ParamKeys.transport)),
        <String>['xhttp', 'xhttp', 'tcp'],
      );
    });

    test('builds a document the core accepts out of all of them', () {
      final nodes = SubscriptionBodyReader().read(list).nodes;
      final result = const SingBoxConfigBuilder().build(
        SingBoxBuildRequest(
          nodes: nodes,
          selectedNodeId: nodes.first.id,
          routing: RoutingPolicy.defaults,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          platform: ConfigPlatform.android,
        ),
      );
      final built = result.valueOrNull;

      expect(result.failureOrNull, isNull);
      expect(built!.leftOut, isEmpty);
      final outbounds = (built.config.document['outbounds']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(outbounds[0]['transport'], <String, Object?>{
        'type': 'xhttp',
        'path': '/api/v2',
        'x_padding_bytes': '100-1000',
        'sc_max_each_post_bytes': 1000000,
        'sc_min_posts_interval_ms': 30,
        'xmux': <String, Object?>{
          'max_concurrency': '16-32',
          'h_max_request_times': '600-900',
          'h_max_reusable_secs': '1800-3000',
        },
      });
      expect(outbounds[1]['transport'], <String, Object?>{
        'type': 'xhttp',
        'mode': 'packet-up',
        'host': 'front.example.com',
        'path': '/cdn',
      });
      expect(outbounds[2].containsKey('transport'), isFalse);
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
