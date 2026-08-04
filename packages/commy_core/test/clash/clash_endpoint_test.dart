import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClashEndpoint', () {
    test('defaults to loopback, never to an outside host', () {
      final endpoint = ClashEndpoint.loopback();

      expect(endpoint.base.host, '127.0.0.1');
      expect(endpoint.base.port, ClashEndpoint.defaultPort);
    });

    test('builds the paths the Clash API exposes', () {
      final endpoint = ClashEndpoint.loopback(port: 9095);

      expect(endpoint.proxies.path, '/proxies');
      expect(endpoint.proxyGroup('proxy').path, '/proxies/proxy');
      expect(endpoint.traffic.path, '/traffic');
      expect(endpoint.connections.path, '/connections');
      expect(endpoint.logs().path, '/logs');
      expect(endpoint.logs(level: LogLevel.debug).query, 'level=debug');
    });

    test('escapes a tag that would otherwise break the path', () {
      final endpoint = ClashEndpoint.loopback();

      expect(
        endpoint.proxyGroup('node/one').toString(),
        contains('node%2Fone'),
      );
    });

    test('sends the delay probe and timeout as query parameters', () {
      final uri = ClashEndpoint.loopback().delay(
        'nl-03',
        probe: Uri.parse('http://cp.cloudflare.com/generate_204'),
        timeout: const Duration(seconds: 5),
      );

      expect(uri.path, '/proxies/nl-03/delay');
      expect(uri.queryParameters['timeout'], '5000');
      expect(
        uri.queryParameters['url'],
        'http://cp.cloudflare.com/generate_204',
      );
    });

    test('puts the token in a header, never in the URL', () {
      const secret = 's3cr3t-token-value';
      final endpoint = ClashEndpoint.loopback(secret: secret);

      expect(endpoint.headers['Authorization'], 'Bearer $secret');
      expect(endpoint.proxies.toString(), isNot(contains(secret)));
    });

    test('sends no Authorization header when there is no token yet', () {
      expect(
        ClashEndpoint.loopback().headers,
        isNot(contains('Authorization')),
      );
      expect(
        ClashEndpoint.loopback(secret: '').headers,
        isNot(contains('Authorization')),
      );
    });

    test('never prints the token, because toString ends up in logs', () {
      const secret = 's3cr3t-token-value';

      expect(
        ClashEndpoint.loopback(secret: secret).toString(),
        isNot(contains(secret)),
      );
      expect(
        ClashEndpoint.loopback(secret: secret).toString(),
        contains(Redact.placeholder),
      );
    });

    test('keeps a base path prefix when the helper mounts under one', () {
      final endpoint = ClashEndpoint(
        base: Uri(scheme: 'http', host: '127.0.0.1', port: 9090, path: '/api'),
      );

      expect(endpoint.proxies.path, '/api/proxies');
    });
  });
}
