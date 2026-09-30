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
}
