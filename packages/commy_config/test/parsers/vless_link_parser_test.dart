import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = VlessLinkParser();

  group('VlessLinkParser.parse', () {
    test('reads a full Reality link', () {
      const uuid = '3d1f6a30-0b1c-4a2b-9f7e-8c5d4e3b2a10';
      final node = parser.parse(
        'vless://$uuid@nl-03.example.net:443'
        '?type=tcp&security=reality&pbk=PUBKEY&fp=chrome'
        '&sni=www.microsoft.com&sid=a1b2c3d4&spx=%2F'
        '&flow=xtls-rprx-vision#NL%20%2303',
      );

      expect(node.protocol, Protocol.vless);
      expect(node.host, 'nl-03.example.net');
      expect(node.port, 443);
      expect(node.name, 'NL #03');
      expect(node.param(ParamKeys.uuid), uuid);
      expect(node.param(ParamKeys.security), 'reality');
      expect(node.param(ParamKeys.transport), 'tcp');
      expect(node.param(ParamKeys.publicKey), 'PUBKEY');
      expect(node.param(ParamKeys.shortId), 'a1b2c3d4');
      expect(node.param(ParamKeys.spiderX), '/');
      expect(node.param(ParamKeys.fingerprint), 'chrome');
      expect(node.param(ParamKeys.flow), 'xtls-rprx-vision');
      expect(node.param(ParamKeys.sni), 'www.microsoft.com');
    });

    test('a public key implies Reality even when security says tls', () {
      final node = parser.parse(
        'vless://uuid@example.com:443?security=tls&pbk=KEY#x',
      );

      expect(node.param(ParamKeys.security), 'reality');
    });

    test('silence about security means plaintext for vless', () {
      final node = parser.parse('vless://uuid@example.com:80#x');

      expect(node.param(ParamKeys.security), 'none');
      expect(node.param(ParamKeys.transport), 'tcp');
    });

    test('reads a websocket link and its host header', () {
      final node = parser.parse(
        'vless://uuid@example.com:443?type=ws&security=tls'
        '&path=%2Fray%3Fed%3D2048&host=cdn.example.com#ws',
      );

      expect(node.param(ParamKeys.transport), 'ws');
      expect(node.param(ParamKeys.path), '/ray?ed=2048');
      expect(node.param(ParamKeys.host), 'cdn.example.com');
    });

    test('folds the grpc service name out of serviceName', () {
      final node = parser.parse(
        'vless://uuid@example.com:443?type=grpc&serviceName=grpcSvc'
        '&security=tls#grpc',
      );

      expect(node.param(ParamKeys.serviceName), 'grpcSvc');
      expect(node.param(ParamKeys.path), isNull);
    });

    test('keeps an IPv6 literal without its brackets', () {
      final node = parser.parse('vless://uuid@[2001:db8::1]:443#v6');

      expect(node.host, '2001:db8::1');
      expect(node.port, 443);
    });

    test('accepts an uppercase scheme and a padded port', () {
      final node = parser.parse('VLESS://uuid@example.com: 443 #pad');

      expect(node.protocol, Protocol.vless);
      expect(node.port, 443);
    });

    test('falls back to host:port when there is no fragment', () {
      final node = parser.parse('vless://uuid@example.com:443');

      expect(node.name, 'example.com');
    });

    test('takes the first non-empty value of a duplicated key', () {
      final node = parser.parse(
        'vless://uuid@example.com:443?sni=&sni=real.example#dup',
      );

      expect(node.param(ParamKeys.sni), 'real.example');
    });

    test('joins repeated alpn values', () {
      final node = parser.parse(
        'vless://uuid@example.com:443?security=tls&alpn=h2&alpn=http%2F1.1#a',
      );

      expect(node.param(ParamKeys.alpn), 'h2,http/1.1');
    });

    test('rejects a link with no user id', () {
      expect(
        () => parser.parse('vless://@example.com:443#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no port', () {
      expect(
        () => parser.parse('vless://uuid@example.com#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a port outside the legal range', () {
      expect(
        () => parser.parse('vless://uuid@example.com:70000#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a transport the core cannot carry', () {
      expect(
        () => parser.parse('vless://uuid@example.com:443?type=xhttp#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects another protocol', () {
      expect(
        () => parser.parse('trojan://pass@example.com:443#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('VlessLinkParser.toLink', () {
    test('round trips a Reality node', () {
      const link = 'vless://uuid@example.com:443?type=tcp&security=reality'
          '&sni=a.example&fp=chrome&pbk=KEY&sid=ab12#Node';
      final node = parser.parse(link);
      final again = parser.parse(parser.toLink(node));

      expect(again.host, node.host);
      expect(again.port, node.port);
      expect(again.name, node.name);
      expect(again.params, node.params);
      expect(again.id, node.id);
    });

    test('brackets an IPv6 host on the way out', () {
      final node = parser.parse('vless://uuid@[2001:db8::1]:443#v6');

      expect(parser.toLink(node), contains('@[2001:db8::1]:443'));
    });

    test('refuses a node with no user id', () {
      const node = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.vless,
        host: 'example.com',
        port: 443,
      );

      expect(
        () => parser.toLink(node),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
