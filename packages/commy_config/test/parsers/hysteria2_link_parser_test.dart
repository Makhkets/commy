import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = Hysteria2LinkParser();

  group('Hysteria2LinkParser', () {
    test('reads a full link', () {
      final node = parser.parse(
        'hysteria2://s3cret@hy.example.com:8443?sni=hy.example.com'
        '&insecure=1&obfs=salamander&obfs-password=obfpass'
        '&up=100&down=500#Hysteria',
      );

      expect(node.protocol, Protocol.hysteria2);
      expect(node.host, 'hy.example.com');
      expect(node.port, 8443);
      expect(node.param(ParamKeys.password), 's3cret');
      expect(node.param(ParamKeys.sni), 'hy.example.com');
      expect(node.params[ParamKeys.allowInsecure], isTrue);
      expect(node.param(ParamKeys.obfs), 'salamander');
      expect(node.param(ParamKeys.obfsPassword), 'obfpass');
      expect(node.params[ParamKeys.upMbps], 100);
      expect(node.params[ParamKeys.downMbps], 500);
    });

    test('accepts the hy2 scheme', () {
      final node = parser.parse('hy2://pw@hy.example.com:443#H');

      expect(node.protocol, Protocol.hysteria2);
    });

    test('keeps a colon inside the authentication string', () {
      final node = parser.parse('hysteria2://user:pass@hy.example.com:443#H');

      expect(node.param(ParamKeys.password), 'user:pass');
    });

    test('falls back to the auth query parameter', () {
      final node = parser.parse('hysteria2://hy.example.com:443?auth=tok#H');

      expect(node.param(ParamKeys.password), 'tok');
      expect(node.host, 'hy.example.com');
    });

    test('reads port hopping ranges', () {
      final node = parser.parse(
        'hysteria2://pw@hy.example.com:443?mport=2080-3000#H',
      );

      expect(node.param(ParamKeys.serverPorts), '2080-3000');
    });

    test('rejects a link with no credential at all', () {
      expect(
        () => parser.parse('hysteria2://hy.example.com:443#H'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no port', () {
      expect(
        () => parser.parse('hysteria2://pw@hy.example.com#H'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('round trips', () {
      final node = parser.parse(
        'hysteria2://pw@hy.example.com:443?sni=s.example&obfs=salamander'
        '&obfs-password=o&insecure=1#Node',
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.params, node.params);
      expect(again.name, node.name);
      expect(again.id, node.id);
    });
  });
}
