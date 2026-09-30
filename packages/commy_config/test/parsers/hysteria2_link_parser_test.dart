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

    test('defaults a missing port to 443, as the URI scheme says', () {
      final node = parser.parse('hysteria2://letmein@example.com/?sni=a.ex#H');

      expect(node.host, 'example.com');
      expect(node.port, 443);
      expect(node.param(ParamKeys.sni), 'a.ex');
      expect(node.param(ParamKeys.serverPorts), isNull);
    });

    test('reads the port list the official client puts in the authority', () {
      // The example from the Hysteria 2 URI scheme itself.
      final node = parser.parse(
        'hysteria2://letmein@example.com:123,5000-6000/?insecure=1'
        '&obfs=salamander&obfs-password=gawrgura&sni=real.example.com',
      );

      expect(node.host, 'example.com');
      expect(node.port, 123);
      expect(node.param(ParamKeys.password), 'letmein');
      expect(node.param(ParamKeys.serverPorts), '123,5000-6000');
      expect(node.param(ParamKeys.sni), 'real.example.com');
      expect(node.param(ParamKeys.obfs), 'salamander');
      expect(node.param(ParamKeys.obfsPassword), 'gawrgura');
      expect(node.params[ParamKeys.allowInsecure], isTrue);
    });

    test('starts a port list that opens with a range at its first port', () {
      final node = parser.parse('hy2://pw@[2001:db8::1]:20000-50000?sni=s#H');

      expect(node.host, '2001:db8::1');
      expect(node.port, 20000);
      expect(node.param(ParamKeys.serverPorts), '20000-50000');
    });

    test('lets mport win over a port list in the authority', () {
      final node = parser.parse(
        'hysteria2://pw@hy.example.com:443,8443?mport=2080-3000#H',
      );

      expect(node.port, 443);
      expect(node.param(ParamKeys.serverPorts), '2080-3000');
    });

    test('still refuses a port that is neither a number nor a list', () {
      expect(
        () => parser.parse('hysteria2://pw@hy.example.com:abc#H'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('hands the core a hop list it accepts', () {
      final node = parser.parse(
        'hysteria2://letmein@example.com:123,5000-6000/?sni=real.example.com',
      );
      final outbound = OutboundBuilder.build(node: node, tag: 'proxy-out');

      expect(outbound['server_port'], 123);
      expect(outbound['server_ports'], <String>['123:123', '5000:6000']);
    });

    test('round trips a port list from the authority', () {
      final node =
          parser.parse('hysteria2://pw@hy.example.com:123,5000-6000#H');
      final again = parser.parse(parser.toLink(node));

      expect(again.port, node.port);
      expect(again.params, node.params);
      expect(again.id, node.id);
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
