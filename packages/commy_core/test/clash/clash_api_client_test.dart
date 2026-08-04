import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `ClashApiClient` against a real HTTP server on loopback.
///
/// Loopback, in-process, torn down after each test — nothing here leaves the
/// machine, so rule R1 is not in play. Mocking `HttpClient` instead would test
/// the mock: the parts that break in reality are chunked bodies, status codes
/// and header handling, and none of those exist in a hand-written double.
void main() {
  late HttpServer server;
  late ClashApiClient client;
  late List<HttpRequest> seen;

  /// Answers every request with whatever [respond] writes.
  Future<void> serve(
    FutureOr<void> Function(HttpRequest request) respond, {
    String? secret,
  }) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    seen = <HttpRequest>[];
    unawaited(
      server.forEach((request) async {
        seen.add(request);
        await respond(request);
      }),
    );
    client = ClashApiClient(
      endpoint: ClashEndpoint.loopback(port: server.port, secret: secret),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
  }

  /// Answers one JSON body with [status].
  Future<void> serveJson(
    String body, {
    int status = 200,
    String? secret,
  }) =>
      serve(
        (request) async {
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write(body);
          await request.response.close();
        },
        secret: secret,
      );

  /// Answers a newline-delimited stream, the way `/traffic` and `/logs` do.
  Future<void> serveLines(List<String> lines) => serve(
        (request) async {
          lines.forEach(request.response.writeln);
          await request.response.close();
        },
      );

  group('ClashApiClient requests', () {
    test('reads the proxy groups', () async {
      await serveJson(
        '{"proxies":{"proxy":{"type":"Selector","now":"nl-03",'
        '"all":["nl-03","de-01"]}}}',
      );

      final groups = await client.proxies();

      expect(groups.single.tag, 'proxy');
      expect(seen.single.uri.path, '/proxies');
    });

    test('sends the token as a bearer header', () async {
      await serveJson('{"proxies":{}}', secret: 's3cr3t');

      await client.proxies();

      expect(seen.single.headers.value('authorization'), 'Bearer s3cr3t');
    });

    test('select is a PUT carrying the member name', () async {
      final bodies = <String>[];
      await serve((request) async {
        bodies.add(await utf8.decoder.bind(request).join());
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
      });

      await client.select('proxy', 'de-01');

      expect(seen.single.method, 'PUT');
      expect(seen.single.uri.path, '/proxies/proxy');
      expect(jsonDecode(bodies.single), <String, Object?>{'name': 'de-01'});
    });

    test('urlTest reads the delay', () async {
      await serveJson('{"delay":137}');

      final delay = await client.urlTest(
        'nl-03',
        Uri.parse('http://cp.cloudflare.com/generate_204'),
      );

      expect(delay, const Duration(milliseconds: 137));
      expect(seen.single.uri.path, '/proxies/nl-03/delay');
    });

    test('a probe timeout is null, not a failure', () async {
      await serveJson('{"message":"timeout"}', status: 408);

      expect(
        await client.urlTest('nl-03', Uri.parse('http://x/')),
        isNull,
      );
    });
  });

  group('ClashApiClient failures', () {
    test('a refused connection means the helper is not there', () async {
      // Bind and immediately close, so the port is certainly dead.
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      final orphan = ClashApiClient(
        endpoint: ClashEndpoint.loopback(port: port),
      );
      addTearDown(orphan.dispose);

      await expectLater(
        orphan.proxies(),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const HelperUnavailableFailure(),
          ),
        ),
      );
    });

    test('a rejected token reads as the helper being unavailable', () async {
      await serveJson('{"message":"Unauthorized"}', status: 401);

      await expectLater(
        client.proxies(),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const HelperUnavailableFailure(),
          ),
        ),
      );
    });

    test('a missing group is a config failure carrying the message', () async {
      await serveJson('{"message":"proxy not found"}', status: 404);

      await expectLater(
        client.select('nowhere', 'de-01'),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            const ConfigInvalidFailure('proxy not found'),
          ),
        ),
      );
    });

    test('an unexpected status still produces a typed failure', () async {
      await serveJson('{"message":"boom"}', status: 500);

      await expectLater(
        client.proxies(),
        throwsA(
          isA<CoreClientException>().having(
            (exception) => exception.failure,
            'failure',
            isA<UnknownFailure>(),
          ),
        ),
      );
    });
  });

  group('ClashApiClient streams', () {
    test('reads the newline-delimited traffic stream', () async {
      await serveLines(<String>[
        '{"up":100,"down":200}',
        '{"up":300,"down":400}',
      ]);

      final samples = await client.traffic.toList();

      expect(samples.map((sample) => sample.uplink), <int>[100, 300]);
    });

    test('reads the log stream in Clash spelling', () async {
      await serveLines(<String>[
        '{"type":"info","payload":"started"}',
        '{"type":"error","payload":"dial failed"}',
      ]);

      final lines = await client.logs().toList();

      expect(lines.last.level, LogLevel.error);
      expect(lines.last.message, 'dial failed');
    });

    test('connection snapshots feed the totals the traffic stream lacks',
        () async {
      // Clash reports rates on /traffic and cumulative counters only on
      // /connections, so the client has to carry them across.
      await serve((request) async {
        final body = request.uri.path == '/connections'
            ? '{"downloadTotal":5368709120,"uploadTotal":1073741824,'
                '"connections":[{"id":"c-1","metadata":{"host":"example.com",'
                '"destinationPort":"443","network":"tcp"},'
                '"rule":"GeoSite","rulePayload":"ru","chains":["proxy"]}]}'
            : '{"up":100,"down":200}';
        request.response.writeln(body);
        await request.response.close();
      });

      final snapshot = await client.connections.first;
      final sample = await client.traffic.first;

      expect(snapshot.single.host, 'example.com:443');
      expect(sample.uplinkTotal, 1073741824);
      expect(sample.downlinkTotal, 5368709120);
    });

    test('drops a malformed line rather than killing the stream', () async {
      await serveLines(<String>[
        'not json',
        '{"up":1,"down":2}',
      ]);

      final samples = await client.traffic.toList();

      expect(samples.single.uplink, 1);
    });
  });
}
