import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = ShadowsocksLinkParser();

  group('ShadowsocksLinkParser.parse', () {
    test('reads the SIP002 form with a base64 user info', () {
      final userInfo = LenientBase64.encodeUrlSafe(
        'chacha20-ietf-poly1305:p@ssw0rd:with:colons',
      );
      final node = parser.parse('ss://$userInfo@ss.example.com:8388#Berlin');

      expect(node.protocol, Protocol.shadowsocks);
      expect(node.host, 'ss.example.com');
      expect(node.port, 8388);
      expect(node.name, 'Berlin');
      expect(node.param(ParamKeys.method), 'chacha20-ietf-poly1305');
      expect(node.param(ParamKeys.password), 'p@ssw0rd:with:colons');
    });

    test('reads the SIP002 form with a plain user info', () {
      final node = parser.parse(
        'ss://aes-256-gcm:secret@ss.example.com:8388#Plain',
      );

      expect(node.param(ParamKeys.method), 'aes-256-gcm');
      expect(node.param(ParamKeys.password), 'secret');
    });

    test('reads the legacy form where the whole body is base64', () {
      final body = LenientBase64.encode(
        'aes-128-gcm:legacypass@10.0.0.1:9000',
      );
      final node = parser.parse('ss://$body#Legacy');

      expect(node.host, '10.0.0.1');
      expect(node.port, 9000);
      expect(node.param(ParamKeys.method), 'aes-128-gcm');
      expect(node.param(ParamKeys.password), 'legacypass');
      expect(node.name, 'Legacy');
    });

    test('reads a SIP003 plugin and its options', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');
      final node = parser.parse(
        'ss://$userInfo@ss.example.com:8388'
        '?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dbing.com#Obfs',
      );

      expect(node.param(ParamKeys.plugin), 'obfs-local');
      expect(node.param(ParamKeys.pluginOpts), 'obfs=http;obfs-host=bing.com');
    });

    test('reads a v2ray-plugin without options', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');
      final node = parser.parse(
        'ss://$userInfo@ss.example.com:8388?plugin=v2ray-plugin#V2',
      );

      expect(node.param(ParamKeys.plugin), 'v2ray-plugin');
      expect(node.param(ParamKeys.pluginOpts), isNull);
    });

    test('keeps an IPv6 literal', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');
      final node = parser.parse('ss://$userInfo@[2001:db8::5]:8388#v6');

      expect(node.host, '2001:db8::5');
      expect(node.port, 8388);
    });

    test('rejects a user info that is not cipher:password', () {
      final userInfo = LenientBase64.encodeUrlSafe('nocolonhere');

      expect(
        () => parser.parse('ss://$userInfo@example.com:8388#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a legacy body that is not base64', () {
      expect(
        () => parser.parse('ss://!!!!#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('rejects a link with no port', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');

      expect(
        () => parser.parse('ss://$userInfo@example.com#x'),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('ShadowsocksLinkParser.toLink', () {
    test('round trips a plugin node', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');
      final node = parser.parse(
        'ss://$userInfo@ss.example.com:8388'
        '?plugin=obfs-local%3Bobfs%3Dhttp#Node',
      );
      final again = parser.parse(parser.toLink(node));

      expect(again.params, node.params);
      expect(again.name, node.name);
      expect(again.id, node.id);
    });

    test('emits SIP002 with a url-safe user info', () {
      final userInfo = LenientBase64.encodeUrlSafe('aes-256-gcm:pw');
      final node = parser.parse('ss://$userInfo@ss.example.com:8388#Node');

      expect(parser.toLink(node), startsWith('ss://$userInfo@'));
    });

    test('refuses a node with no cipher', () {
      const node = ProxyNode(
        id: 'x',
        name: 'x',
        protocol: Protocol.shadowsocks,
        host: 'example.com',
        port: 8388,
        params: <String, Object?>{'password': 'pw'},
      );

      expect(
        () => parser.toLink(node),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });
}
