import 'dart:io';
import 'dart:typed_data';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/stub_http_adapter.dart';

/// A body that arrives in [chunks] pieces of [size] bytes, one per event-loop
/// turn, counting in [pulled] how many the client took.
///
/// One per turn so that the reader gets to look at each piece before the next
/// is made: a client that stops reading must be seen to stop the source, not
/// merely to throw away what it already has. Counted after the `yield`, which
/// is where a generator whose listener has gone away stops.
Stream<Uint8List> countedBody({
  required int chunks,
  required int size,
  required void Function() pulled,
  Duration every = Duration.zero,
}) async* {
  for (var i = 0; i < chunks; i++) {
    await Future<void>.delayed(every);
    yield Uint8List(size)..fillRange(0, size, 0x61);
    pulled();
  }
}

CommyHttpClient clientOver(
  StubHttpAdapter adapter, {
  int maxBodyBytes = CommyHttpClient.defaultMaxBodyBytes,
  Duration totalTimeout = CommyHttpClient.defaultTotalTimeout,
}) =>
    CommyHttpClient(
      maxBodyBytes: maxBodyBytes,
      totalTimeout: totalTimeout,
      directClient: Dio()..httpClientAdapter = adapter,
    );

HttpTransportError? causeOf(CommyFailure? failure) =>
    (failure! as SubscriptionUnreachableFailure).cause as HttpTransportError?;

void main() {
  group('the body cap', () {
    test('a body past the cap is dropped while it arrives, not after',
        () async {
      // A link to a release asset pasted as a subscription, or a gzip body
      // that inflates to hundreds of megabytes: dio's `plain` read all of it
      // into memory — plus a UTF-16 copy — before the cap was even looked at.
      var pulled = 0;
      const chunks = 400;
      final adapter = StubHttpAdapter(
        (_) async => ResponseBody(
          countedBody(chunks: chunks, size: 1024, pulled: () => pulled++),
          200,
        ),
      );
      final client = clientOver(adapter, maxBodyBytes: 16 * 1024);

      final text = await client.fetchText(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(
        causeOf(text.failureOrNull)?.kind,
        HttpTransportError.kindTooLarge,
      );
      expect(pulled, lessThan(chunks ~/ 4), reason: 'read $pulled of $chunks');
    });

    test('a Content-Length past the cap is refused before the body', () async {
      var pulled = 0;
      final adapter = StubHttpAdapter(
        (_) async => ResponseBody(
          countedBody(chunks: 64, size: 1024, pulled: () => pulled++),
          200,
          headers: <String, List<String>>{
            HttpHeaders.contentLengthHeader: <String>['${64 * 1024}'],
          },
        ),
      );
      final client = clientOver(adapter, maxBodyBytes: 16 * 1024);

      final bytes = await client.fetchBytes(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(
        causeOf(bytes.failureOrNull)?.kind,
        HttpTransportError.kindTooLarge,
      );
      expect(pulled, lessThan(4), reason: 'read $pulled chunks');
    });

    test('the binary fetch stops at the cap too', () async {
      var pulled = 0;
      const chunks = 400;
      final adapter = StubHttpAdapter(
        (_) async => ResponseBody(
          countedBody(chunks: chunks, size: 1024, pulled: () => pulled++),
          200,
        ),
      );
      final client = clientOver(adapter, maxBodyBytes: 16 * 1024);

      final bytes = await client.fetchBytes(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(
        causeOf(bytes.failureOrNull)?.kind,
        HttpTransportError.kindTooLarge,
      );
      expect(pulled, lessThan(chunks ~/ 4), reason: 'read $pulled of $chunks');
    });

    test('the cap counts bytes, and a body right at it is kept', () async {
      // Two bytes per character in UTF-8: the old check measured the decoded
      // string and let a body of twice the cap through.
      final client = clientOver(
        StubHttpAdapter.text('я' * 16),
        maxBodyBytes: 32,
      );

      final text = await client.fetchText(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );
      expect(text.valueOrNull?.body, 'я' * 16);

      final over = await clientOver(
        StubHttpAdapter.text('я' * 17),
        maxBodyBytes: 32,
      ).fetchText(Fixtures.subscriptionUrl, throughTunnel: false);
      expect(
        causeOf(over.failureOrNull)?.kind,
        HttpTransportError.kindTooLarge,
      );
    });
  });

  group('the deadline', () {
    test('a server that trickles forever is given up on', () async {
      // A byte every so often never trips the receive timeout, which dio
      // restarts on every chunk. The fetch never ended, and with it every
      // other refresh queued behind it.
      var pulled = 0;
      final adapter = StubHttpAdapter(
        (_) async => ResponseBody(
          countedBody(
            chunks: 1 << 30,
            size: 1,
            pulled: () => pulled++,
            every: const Duration(milliseconds: 20),
          ),
          200,
        ),
      );
      final client = clientOver(
        adapter,
        totalTimeout: const Duration(milliseconds: 400),
      );

      final text = await client
          .fetchText(Fixtures.subscriptionUrl, throughTunnel: false)
          .timeout(const Duration(seconds: 10));

      final cause = causeOf(text.failureOrNull);
      expect(cause?.kind, HttpTransportError.kindTimeout);
      expect(cause?.detail, contains('total'));
      final seen = pulled;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(pulled, seen, reason: 'the body kept being read after giving up');
    });

    test("the caller's own token still cancels", () async {
      final adapter = StubHttpAdapter(
        (_) async => ResponseBody(
          countedBody(
            chunks: 1 << 30,
            size: 1,
            pulled: () {},
            every: const Duration(milliseconds: 20),
          ),
          200,
        ),
      );
      final token = CancelToken();
      final pending = clientOver(adapter).fetchText(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
        cancelToken: token,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      token.cancel();

      final text = await pending.timeout(const Duration(seconds: 10));
      expect(
        causeOf(text.failureOrNull)?.kind,
        HttpTransportError.kindCancelled,
      );
    });
  });

  group('redirects', () {
    const identity = <String, String>{
      'x-hwid': 'install-id',
      'x-device-os': 'Android',
      'x-ver-os': '15',
      'x-device-model': 'Pixel 8',
    };

    /// A server that answers [hops] in turn, by full URL, and 404 otherwise.
    StubHttpAdapter server(Map<String, ResponseBody Function()> hops) =>
        StubHttpAdapter((options) async {
          final answer = hops[options.uri.toString()];
          return answer == null ? ResponseBody.fromString('no', 404) : answer();
        });

    ResponseBody Function() redirectTo(String location, {int status = 302}) =>
        () => ResponseBody.fromString(
              '',
              status,
              headers: <String, List<String>>{
                HttpHeaders.locationHeader: <String>[location],
              },
            );

    ResponseBody Function() answer(String body) =>
        () => ResponseBody.fromString(body, 200);

    Future<Result<HttpTextResponse, CommyFailure>> fetch(
      StubHttpAdapter adapter,
      String url,
    ) =>
        clientOver(adapter).fetchText(
          Uri.parse(url),
          throughTunnel: false,
          extraHeaders: identity,
        );

    Map<String, dynamic> sentOn(StubHttpAdapter adapter, int hop) =>
        adapter.requests[hop].headers;

    test('a redirect to another host is followed without the device identity',
        () async {
      // ADR-0009 and the settings screen promise the identifier to the
      // subscription's host only. dart:io copied every header but the
      // credentials it knows about to wherever `Location` pointed — a CDN,
      // a mirror, the target of a short link — on every refresh.
      final adapter = server(<String, ResponseBody Function()>{
        'https://sub.provider.example/abc':
            redirectTo('https://cdn.other-host.net/abc'),
        'https://cdn.other-host.net/abc': answer('vless://a@b:443#One'),
      });

      final result = await fetch(adapter, 'https://sub.provider.example/abc');

      expect(result.valueOrNull?.body, 'vless://a@b:443#One');
      expect(
        result.valueOrNull?.url,
        Uri.parse('https://cdn.other-host.net/abc'),
      );
      expect(adapter.requests, hasLength(2));
      expect(sentOn(adapter, 0)['x-hwid'], 'install-id');
      for (final name in identity.keys) {
        expect(sentOn(adapter, 1).containsKey(name), isFalse, reason: name);
      }
      // What is not the identity still goes: the panel still has to know
      // what is asking.
      expect(sentOn(adapter, 1)[HttpHeaders.userAgentHeader], isNotNull);
    });

    test('a subdomain is another host', () async {
      final adapter = server(<String, ResponseBody Function()>{
        'https://provider.example/abc':
            redirectTo('https://cdn.provider.example/abc'),
        'https://cdn.provider.example/abc': answer('vless://a@b:443#One'),
      });

      await fetch(adapter, 'https://provider.example/abc');

      expect(sentOn(adapter, 1).containsKey('x-hwid'), isFalse);
    });

    test('a redirect on the same host keeps it', () async {
      // `/sub/token` to `/sub/token/`, a relative Location: the panel the
      // user typed in, which a device-limited panel needs the identity from.
      final adapter = server(<String, ResponseBody Function()>{
        'https://panel.example.com:8443/sub/token': redirectTo('/sub/token/'),
        'https://panel.example.com:8443/sub/token/':
            redirectTo('https://panel.example.com/final', status: 301),
        'https://panel.example.com/final': answer('vless://a@b:443#One'),
      });

      final result =
          await fetch(adapter, 'https://Panel.Example.com:8443/sub/token');

      expect(result.valueOrNull?.body, 'vless://a@b:443#One');
      expect(adapter.requests, hasLength(3));
      for (var hop = 0; hop < 3; hop++) {
        expect(sentOn(adapter, hop)['x-hwid'], 'install-id', reason: '$hop');
      }
    });

    test('https is never left for plain http', () async {
      // Past that hop the token in the path and the list of credentials in
      // the answer cross the network in the clear, on one header's say-so.
      final adapter = server(<String, ResponseBody Function()>{
        'https://panel.example.com/sub/token':
            redirectTo('http://panel.example.com/sub/token'),
        'http://panel.example.com/sub/token': answer('vless://a@b:443#One'),
      });

      final result =
          await fetch(adapter, 'https://panel.example.com/sub/token');

      expect(
        causeOf(result.failureOrNull)?.kind,
        HttpTransportError.kindInsecureRedirect,
      );
      expect(adapter.requests, hasLength(1));
    });

    test('plain http may still be upgraded', () async {
      final adapter = server(<String, ResponseBody Function()>{
        'http://panel.example.com/sub/token':
            redirectTo('https://panel.example.com/sub/token', status: 308),
        'https://panel.example.com/sub/token': answer('vless://a@b:443#One'),
      });

      final result = await fetch(adapter, 'http://panel.example.com/sub/token');

      expect(result.valueOrNull?.body, 'vless://a@b:443#One');
      expect(sentOn(adapter, 1)['x-hwid'], 'install-id');
    });

    test('a loop ends at the budget', () async {
      final adapter = server(<String, ResponseBody Function()>{
        'https://a.example/x': redirectTo('https://a.example/y'),
        'https://a.example/y': redirectTo('https://a.example/x'),
      });

      final result = await fetch(adapter, 'https://a.example/x');

      expect(
        causeOf(result.failureOrNull)?.kind,
        HttpTransportError.kindRedirect,
      );
      expect(
        adapter.requests,
        hasLength(CommyHttpClient.defaultMaxRedirects + 1),
      );
    });

    test('a Location to a scheme we do not fetch is not followed', () async {
      final adapter = server(<String, ResponseBody Function()>{
        'https://a.example/x': redirectTo('file:///etc/passwd'),
      });

      final result = await fetch(adapter, 'https://a.example/x');

      expect(
        causeOf(result.failureOrNull)?.kind,
        HttpTransportError.kindRedirect,
      );
      expect(result.failureOrNull.toString(), isNot(contains('passwd')));
      expect(adapter.requests, hasLength(1));
    });

    test('the rule-set fetch follows a redirect too', () async {
      // GitHub release assets live behind a redirect to another host; the
      // binary fetch never carried the identity, and still does not.
      final adapter = server(<String, ResponseBody Function()>{
        'https://github.example/geosite-ru.srs':
            redirectTo('https://objects.github.example/geosite-ru.srs'),
        'https://objects.github.example/geosite-ru.srs': answer('SRS'),
      });

      final bytes = await clientOver(adapter).fetchBytes(
        Uri.parse('https://github.example/geosite-ru.srs'),
        throughTunnel: false,
      );

      expect(bytes.valueOrNull, 'SRS'.codeUnits);
    });
  });
}
