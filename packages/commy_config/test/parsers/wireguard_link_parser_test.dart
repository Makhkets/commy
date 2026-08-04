import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = WireguardLinkParser();

  group('WireguardLinkParser', () {
    test('reads a full link', () {
      final node = parser.parse(
        'wireguard://PRIVATEKEY@wg.example.com:51820?publickey=PEERKEY'
        '&presharedkey=PSK&address=10.0.0.2%2F32%2Cfd00%3A%3A2%2F128'
        '&mtu=1420&reserved=0%2C0%2C0&keepalive=25#WG',
      );

      expect(node.protocol, Protocol.wireguard);
      expect(node.host, 'wg.example.com');
      expect(node.port, 51820);
      expect(node.param(ParamKeys.privateKey), 'PRIVATEKEY');
      expect(node.param(ParamKeys.peerPublicKey), 'PEERKEY');
      expect(node.param(ParamKeys.preSharedKey), 'PSK');
      expect(node.param(ParamKeys.localAddress), '10.0.0.2/32,fd00::2/128');
      expect(node.param(ParamKeys.reserved), '0,0,0');
      expect(node.params[ParamKeys.mtu], 1420);
      expect(node.params[ParamKeys.keepAlive], 25);
    });

    test('accepts the wg scheme and a private key in the query', () {
      final node = parser.parse(
        'wg://wg.example.com:51820?privatekey=PK&public-key=PEER'
        '&ip=10.0.0.2%2F32#WG',
      );

      expect(node.param(ParamKeys.privateKey), 'PK');
      expect(node.param(ParamKeys.peerPublicKey), 'PEER');
    });

    test('refuses to guess a missing peer public key', () {
      expect(
        () => parser.parse(
          'wireguard://PK@wg.example.com:51820?address=10.0.0.2%2F32#WG',
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('refuses to guess a missing local address', () {
      expect(
        () => parser.parse(
          'wireguard://PK@wg.example.com:51820?publickey=PEER#WG',
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no private key', () {
      expect(
        () => parser.parse(
          'wireguard://wg.example.com:51820'
          '?publickey=P&address=10.0.0.2%2F32#W',
        ),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('round trips', () {
      final node = parser.parse(
        'wireguard://PK@wg.example.com:51820?publickey=PEER'
        '&address=10.0.0.2%2F32&mtu=1420#Node',
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.params, node.params);
      expect(again.name, node.name);
      expect(again.id, node.id);
    });
  });
}
