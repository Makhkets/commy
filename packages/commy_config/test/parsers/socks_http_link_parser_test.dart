import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

void main() {
  const socks = SocksLinkParser();
  const http = HttpLinkParser();
  const shadowtls = ShadowtlsLinkParser();

  group('SocksLinkParser', () {
    test('reads credentials and defaults to version 5', () {
      final node = socks.parse('socks5://user:pass@127.0.0.1:1080#Local');

      expect(node.protocol, Protocol.socks);
      expect(node.host, '127.0.0.1');
      expect(node.port, 1080);
      expect(node.param(ParamKeys.username), 'user');
      expect(node.param(ParamKeys.password), 'pass');
      expect(node.param(ParamKeys.socksVersion), '5');
    });

    test('reads a base64 wrapped user info', () {
      final userInfo = LenientBase64.encodeUrlSafe('username:password');
      final node = socks.parse('socks://$userInfo@127.0.0.1:1080#L');

      expect(node.param(ParamKeys.username), 'username');
      expect(node.param(ParamKeys.password), 'password');
    });

    test('works without credentials', () {
      final node = socks.parse('socks5://127.0.0.1:1080#L');

      expect(node.param(ParamKeys.username), isNull);
      expect(node.port, 1080);
    });

    test('rejects a link with no port', () {
      expect(
        () => socks.parse('socks5://127.0.0.1#L'),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('HttpLinkParser', () {
    test('reads a proxy with an explicit port', () {
      final node = http.parse('http://user:pass@proxy.example:3128#Proxy');

      expect(node.protocol, Protocol.http);
      expect(node.port, 3128);
      expect(node.param(ParamKeys.username), 'user');
      expect(node.param(ParamKeys.security), 'none');
    });

    test('marks an https proxy as tls', () {
      final node = http.parse('https://proxy.example:3128#Proxy');

      expect(node.param(ParamKeys.security), 'tls');
    });

    test('tells a subscription URL apart from a proxy', () {
      expect(
        HttpLinkParser.looksLikeProxy('https://panel.example/sub/token'),
        isFalse,
      );
      expect(
        HttpLinkParser.looksLikeProxy('https://panel.example'),
        isFalse,
      );
      expect(
        HttpLinkParser.looksLikeProxy('http://10.0.0.1:8080'),
        isTrue,
      );
    });

    test('refuses to read a subscription URL as a proxy', () {
      expect(
        () => http.parse('https://panel.example:443/sub/token'),
        throwsA(isA<LinkFormatException>()),
      );
    });
  });

  group('ShadowtlsLinkParser', () {
    test('reads a version 3 link', () {
      final node = shadowtls.parse(
        'shadowtls://pw@st.example.com:443?version=3&sni=www.apple.com#ST',
      );

      expect(node.protocol, Protocol.shadowtls);
      expect(node.param(ParamKeys.version), '3');
      expect(node.param(ParamKeys.password), 'pw');
      expect(node.param(ParamKeys.sni), 'www.apple.com');
    });

    test('rejects version 2 without a password', () {
      expect(
        () => shadowtls.parse('shadowtls://st.example.com:443?version=2#ST'),
        throwsA(isA<LinkFormatException>()),
      );
    });

    test('allows version 1 without a password', () {
      final node = shadowtls.parse(
        'shadowtls://st.example.com:443?version=1#ST',
      );

      expect(node.param(ParamKeys.version), '1');
      expect(node.param(ParamKeys.password), isNull);
    });
  });
}
