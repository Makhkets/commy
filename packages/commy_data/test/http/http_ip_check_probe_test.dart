import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stub_http_adapter.dart';

/// An adapter on the direct client that fails the test if it is ever used:
/// an IP check that goes around the tunnel reports the wrong address, which
/// is exactly the defect this probe exists to avoid.
StubHttpAdapter neverDirect() => StubHttpAdapter((options) async {
      fail('the IP check went around the tunnel: ${options.uri}');
    });

/// A client whose tunnel side answers through [adapter].
CommyHttpClient tunnelClient(StubHttpAdapter adapter) {
  return CommyHttpClient(
    tunnelProxy: const ProxyEndpoint.loopback(2080),
    directClient: Dio()..httpClientAdapter = neverDirect(),
    proxiedClient: Dio()..httpClientAdapter = adapter,
  );
}

void main() {
  final endpoint = Uri.parse('https://ip.example/json');

  group('HttpIpCheckProbe', () {
    test('goes through the tunnel and reads an ipinfo-shaped answer', () async {
      final adapter = StubHttpAdapter.text(
        '{"ip":"203.0.113.7","city":"Amsterdam","country":"NL"}',
      );

      final result =
          await HttpIpCheckProbe(client: tunnelClient(adapter)).probe(endpoint);

      expect(adapter.requests.single.uri, endpoint);
      expect(
        result.valueOrNull,
        const IpCheckResult(ip: '203.0.113.7', country: 'NL'),
      );
    });

    test('a dead endpoint is a failure, not an empty result', () async {
      final adapter = StubHttpAdapter.failing(DioExceptionType.connectionError);

      final result =
          await HttpIpCheckProbe(client: tunnelClient(adapter)).probe(endpoint);

      expect(result.isOk, isFalse);
    });

    test('an answer with no address in it is a failure too', () async {
      final adapter = StubHttpAdapter.text('<html>blocked</html>');

      final result =
          await HttpIpCheckProbe(client: tunnelClient(adapter)).probe(endpoint);

      expect(result.failureOrNull, isA<UnknownFailure>());
    });
  });

  group('HttpIpCheckProbe.parse', () {
    test('ip-api.com spells the address "query"', () {
      expect(
        HttpIpCheckProbe.parse(
          '{"status":"success","countryCode":"DE","query":"198.51.100.2"}',
        ),
        const IpCheckResult(ip: '198.51.100.2', country: 'DE'),
      );
    });

    test('a bare address in plain text is enough', () {
      expect(
        HttpIpCheckProbe.parse('2001:db8::1\n'),
        const IpCheckResult(ip: '2001:db8::1'),
      );
    });

    test('a country without an address is nothing', () {
      expect(HttpIpCheckProbe.parse('{"country":"NL"}'), isNull);
    });

    test('an address that is not one is nothing', () {
      expect(HttpIpCheckProbe.parse('{"ip":"not an address"}'), isNull);
      expect(HttpIpCheckProbe.parse('hello'), isNull);
      expect(HttpIpCheckProbe.parse(''), isNull);
    });

    test('the label is the address, and the country only when known', () {
      expect(const IpCheckResult(ip: '203.0.113.7').label, '203.0.113.7');
      expect(
        const IpCheckResult(ip: '203.0.113.7', country: 'NL').label,
        '203.0.113.7 · NL',
      );
    });
  });
}
