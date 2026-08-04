import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = TrojanLinkParser();

  group('TrojanLinkParser', () {
    test('reads a websocket link', () {
      final node = parser.parse(
        'trojan://p%40ssword@tr.example.com:443?security=tls&sni=tr.example.com'
        '&type=ws&path=%2Ftrojan#Trojan',
      );

      expect(node.protocol, Protocol.trojan);
      expect(node.host, 'tr.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.password), 'p@ssword');
      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/trojan');
      expect(node.param(ParamKeys.sni), 'tr.example.com');
    });

    test('silence about security means tls, unlike vless', () {
      final node = parser.parse('trojan://pw@tr.example.com:443#T');

      expect(node.param(ParamKeys.security), 'tls');
    });

    test('reads the path out of the URI when there is no path query', () {
      final node = parser.parse(
        'trojan://pw@tr.example.com:443/from-uri?type=ws#T',
      );

      expect(node.param(ParamKeys.path), '/from-uri');
    });

    test('accepts the trojan-go scheme', () {
      final node = parser.parse('trojan-go://pw@tr.example.com:443#T');

      expect(node.protocol, Protocol.trojan);
    });

    test('reads skip-cert-verify as allowInsecure', () {
      final node = parser.parse(
        'trojan://pw@tr.example.com:443?allowInsecure=1#T',
      );

      expect(node.params[ParamKeys.allowInsecure], isTrue);
    });

    test('rejects a link with no password', () {
      expect(
        () => parser.parse('trojan://@tr.example.com:443#T'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no port', () {
      expect(
        () => parser.parse('trojan://pw@tr.example.com#T'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('round trips', () {
      final node = parser.parse(
        'trojan://pw@tr.example.com:443?type=ws&security=tls&path=%2Fx'
        '&sni=s.example#Node',
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.params, node.params);
      expect(again.name, node.name);
      expect(again.id, node.id);
    });
  });
}
