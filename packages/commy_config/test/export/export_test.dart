import 'dart:convert';

import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _vless = ProxyNode(
  id: 'n1',
  name: 'NL-03',
  protocol: Protocol.vless,
  host: 'nl.example.com',
  port: 443,
  params: <String, Object?>{
    'uuid': 'the-uuid',
    'security': 'reality',
    'sni': 'www.microsoft.com',
    'pbk': 'PUBKEY',
    'sid': 'ab12',
    'type': 'tcp',
  },
);

const _wireguardWithoutKeys = ProxyNode(
  id: 'n2',
  name: 'WG',
  protocol: Protocol.wireguard,
  host: 'wg.example.com',
  port: 51820,
);

void main() {
  final exporter = NodeLinkExporter();

  group('NodeLinkExporter', () {
    test('renders a node as a link that parses back', () {
      final link = exporter.toLink(_vless).valueOrNull!;
      final again = CommyLinkParser().parse(link).valueOrNull!;

      expect(link, startsWith('vless://'));
      expect(again.nodes.single.host, _vless.host);
      expect(again.nodes.single.param(ParamKeys.publicKey), 'PUBKEY');
    });

    test('reports a node it cannot render', () {
      final result = exporter.toLink(_wireguardWithoutKeys);

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('exports the good nodes and explains the rest', () {
      final outcome = exporter.toLinks(
        <ProxyNode>[_vless, _wireguardWithoutKeys],
      );

      expect(outcome.links, hasLength(1));
      expect(outcome.failures, hasLength(1));
      expect(outcome.document.split('\n'), hasLength(1));
      expect(outcome.hasFailures, isTrue);
    });
  });

  group('QrPayload', () {
    test('a single node becomes its share link', () {
      final payload = QrPayload().forNode(_vless).valueOrNull;

      expect(payload, startsWith('vless://'));
    });

    test('several nodes become a base64 wrapped list', () {
      final payload = QrPayload().forNodes(<ProxyNode>[_vless]).valueOrNull!;
      final decoded = LenientBase64.decodeToString(payload);

      expect(decoded, startsWith('vless://'));
    });

    test('refuses a payload too large to scan', () {
      final many = <ProxyNode>[
        for (var index = 0; index < 200; index++)
          _vless.copyWith(id: 'n$index', name: 'Node $index'),
      ];

      expect(QrPayload().forNodes(many).failureOrNull, isNotNull);
    });

    test('refuses a list where nothing can be rendered', () {
      final result = QrPayload().forNodes(
        <ProxyNode>[_wireguardWithoutKeys],
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('a subscription becomes its own URL', () {
      final payload = QrPayload()
          .forSubscription(
            Subscription(
              id: 's1',
              name: 'Panel',
              url: Uri.parse('https://panel.example.com/sub/token'),
            ),
          )
          .valueOrNull;

      expect(payload, 'https://panel.example.com/sub/token');
    });
  });

  group('ConfigRedactor', () {
    const config = CoreConfig(<String, Object?>{
      'outbounds': <Map<String, Object?>>[
        <String, Object?>{
          'type': 'vless',
          'tag': 'proxy',
          'server': 'nl.example.com',
          'server_port': 443,
          'uuid': 'the-uuid',
          'tls': <String, Object?>{
            'enabled': true,
            'reality': <String, Object?>{
              'enabled': true,
              'public_key': 'PUBKEY',
              'short_id': 'ab12',
            },
          },
        },
      ],
      'experimental': <String, Object?>{
        'clash_api': <String, Object?>{
          'external_controller': '127.0.0.1:9090',
          'secret': 'the-secret',
        },
      },
    });

    test('blanks every credential by default', () {
      final exported = ConfigRedactor.export(config);

      expect(exported, isNot(contains('the-uuid')));
      expect(exported, isNot(contains('ab12')));
      expect(exported, isNot(contains('the-secret')));
      expect(exported, contains(Redact.placeholder));
    });

    test('keeps what makes a log useful', () {
      final exported = ConfigRedactor.export(config);

      expect(exported, contains('nl.example.com'));
      expect(exported, contains('PUBKEY'));
      expect(exported, contains('"type": "vless"'));
    });

    test('hides the server address when asked', () {
      final exported = ConfigRedactor.export(config, hideServers: true);

      expect(exported, isNot(contains('nl.example.com')));
      expect(exported, contains(Redact.serverPlaceholder));
    });

    test('can be asked for the raw document', () {
      final exported = ConfigRedactor.export(config, redact: false);

      expect(exported, contains('the-uuid'));
      expect(jsonDecode(exported), config.document);
    });

    test('leaves the shape of the document alone', () {
      final exported =
          jsonDecode(ConfigRedactor.export(config)) as Map<String, Object?>;
      final outbounds = exported['outbounds']! as List<Object?>;

      expect(outbounds, hasLength(1));
      expect(
        (outbounds.single! as Map<String, Object?>)['server_port'],
        443,
      );
    });
  });
}
