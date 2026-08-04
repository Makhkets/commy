import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = TuicLinkParser();

  group('TuicLinkParser', () {
    test('reads a full link', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      final node = parser.parse(
        'tuic://$uuid:secret@tu.example.com:443'
        '?congestion_control=bbr&alpn=h3&sni=tu.example.com'
        '&udp_relay_mode=native#TUIC',
      );

      expect(node.protocol, Protocol.tuic);
      expect(node.host, 'tu.example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.uuid), uuid);
      expect(node.param(ParamKeys.password), 'secret');
      expect(node.param(ParamKeys.congestionControl), 'bbr');
      expect(node.param(ParamKeys.alpn), 'h3');
      expect(node.param(ParamKeys.udpRelayMode), 'native');
    });

    test('drops a congestion controller the core does not know', () {
      final node = parser.parse(
        'tuic://id:pw@tu.example.com:443?congestion_control=magic#T',
      );

      expect(node.param(ParamKeys.congestionControl), isNull);
    });

    test('reads the password out of the query when the pair is missing', () {
      final node = parser.parse('tuic://id@tu.example.com:443?password=pw#T');

      expect(node.param(ParamKeys.uuid), 'id');
      expect(node.param(ParamKeys.password), 'pw');
    });

    test('rejects a link with no user id', () {
      expect(
        () => parser.parse('tuic://:pw@tu.example.com:443#T'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no port', () {
      expect(
        () => parser.parse('tuic://id:pw@tu.example.com#T'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('round trips', () {
      final node = parser.parse(
        'tuic://id:pw@tu.example.com:443?sni=s.example&alpn=h3'
        '&congestion_control=bbr#Node',
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.params, node.params);
      expect(again.name, node.name);
      expect(again.id, node.id);
    });
  });
}
