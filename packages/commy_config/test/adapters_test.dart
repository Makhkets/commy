import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

const _node = ProxyNode(
  id: 'n1',
  name: 'NL',
  protocol: Protocol.vless,
  host: 'nl.example.com',
  port: 443,
  params: <String, Object?>{'uuid': 'the-uuid', 'security': 'tls'},
);

void main() {
  group('CommyLinkParser', () {
    final parser = CommyLinkParser();

    test('parses a single link', () {
      final outcome = parser.parse('vless://uuid@a.example:443#One');

      expect(outcome.valueOrNull!.nodes.single.name, 'One');
    });

    test('parses a base64 subscription body', () {
      final body = LenientBase64.encode(
        'vless://uuid@a.example:443#One\ntrojan://pw@b.example:443#Two',
      );

      expect(parser.parse(body).valueOrNull!.nodes, hasLength(2));
    });

    test('partial success stays a success', () {
      final outcome = parser.parse(
        'vless://uuid@a.example:443#Good\nnot a link\n',
      );

      expect(outcome.isOk, isTrue);
      expect(outcome.valueOrNull!.nodes, hasLength(1));
      expect(outcome.valueOrNull!.failures, hasLength(1));
    });

    test('total nonsense is a failure with a reason', () {
      final outcome = parser.parse('the quick brown fox');

      expect(outcome.isErr, isTrue);
      expect(outcome.failureOrNull, isA<SubscriptionMalformedFailure>());
    });

    test('canParse lights up only for something we can read', () {
      expect(parser.canParse('vless://uuid@a.example:443#One'), isTrue);
      expect(parser.canParse('the quick brown fox'), isFalse);
      expect(parser.canParse(''), isFalse);
    });

    test('renders a node back into a link', () {
      expect(parser.toLink(_node).valueOrNull, startsWith('vless://'));
    });

    test('reports a node that has no share format', () {
      const broken = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.wireguard,
        host: 'a.example',
        port: 51820,
      );

      expect(parser.toLink(broken).failureOrNull, isNotNull);
    });
  });

  group('SingBoxConfigGenerator', () {
    test('satisfies the domain port', () {
      const generator = SingBoxConfigGenerator(
        platform: ConfigPlatform.android,
      );
      final result = generator.build(
        node: _node,
        routing: RoutingPolicy.defaults,
        dns: DnsSettings.defaults,
        settings: AppSettings.defaults,
        includeClashApi: false,
      );
      final config = result.valueOrNull!;

      expect(generator, isA<ConfigGenerator>());
      expect(config.sections, <String>[
        'dns',
        'experimental',
        'inbounds',
        'log',
        'outbounds',
        'route',
      ]);
    });

    test('turns a node it cannot express into a typed failure', () {
      const generator = SingBoxConfigGenerator(
        platform: ConfigPlatform.android,
      );
      const broken = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.vless,
        host: 'a.example',
        port: 443,
      );
      final result = generator.build(
        node: broken,
        routing: RoutingPolicy.defaults,
        dns: DnsSettings.defaults,
        settings: AppSettings.defaults,
        includeClashApi: false,
      );

      expect(result.failureOrNull, isA<ConfigInvalidFailure>());
    });

    test('honours includeClashApi on desktop', () {
      const generator = SingBoxConfigGenerator(
        platform: ConfigPlatform.linux,
        clashApi: ClashApiOptions(secret: 'testsecret'),
      );
      final config = generator
          .build(
            node: _node,
            routing: RoutingPolicy.defaults,
            dns: DnsSettings.defaults,
            settings: AppSettings.defaults,
            includeClashApi: true,
          )
          .valueOrNull!;
      final experimental =
          config.document['experimental']! as Map<String, Object?>;

      expect(experimental.containsKey('clash_api'), isTrue);
    });
  });

  group('ClashApiOptions', () {
    test('binds to loopback and nothing else', () {
      const options = ClashApiOptions(secret: 'topsecret', port: 1234);

      expect(options.externalController, '127.0.0.1:1234');
      expect(options.toString(), isNot(contains('topsecret')));
    });

    test('draws a secret of the documented length', () {
      final options = ClashApiOptions.generate();

      expect(options.secret, hasLength(ClashApiOptions.secretBytes * 2));
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(options.secret), isTrue);
    });

    test('two generated secrets differ', () {
      expect(
        ClashApiOptions.generate().secret,
        isNot(ClashApiOptions.generate().secret),
      );
    });
  });
}
