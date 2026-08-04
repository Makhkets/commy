import 'dart:io';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/stub_http_adapter.dart';

/// A stand-in for the header parser that really lives in commy_config.
///
/// commy_data may not import commy_config (CLAUDE.md §3), so the fetcher takes
/// the parser as a callback. This one understands just enough of
/// `subscription-userinfo` to prove the headers arrive intact.
SubscriptionPayload testMapper(String body, Map<String, Object?> headers) {
  final raw = headers['subscription-userinfo'];
  final fields = <String, int>{};
  if (raw is String) {
    for (final part in raw.split(';')) {
      final split = part.indexOf('=');
      if (split <= 0) {
        continue;
      }
      final parsed = int.tryParse(part.substring(split + 1).trim());
      if (parsed != null) {
        fields[part.substring(0, split).trim()] = parsed;
      }
    }
  }
  final title = headers['profile-title'];
  return SubscriptionPayload(
    body: body,
    profileTitle: title is String ? title : null,
    userInfo: fields.isEmpty
        ? null
        : SubscriptionUserInfo(
            upload: fields['upload'],
            download: fields['download'],
            total: fields['total'],
          ),
  );
}

CommyHttpClient clientWith(StubHttpAdapter adapter, {String? userAgent}) {
  final dio = Dio()..httpClientAdapter = adapter;
  return CommyHttpClient(
    userAgent: userAgent ?? CommyUserAgent.fallback,
    directClient: dio,
  );
}

void main() {
  group('HttpSubscriptionFetcher', () {
    test('returns the body and the parsed headers', () async {
      final adapter = StubHttpAdapter.text(
        'vless://a@b:443#One\nvless://c@d:443#Two',
        headers: <String, List<String>>{
          'subscription-userinfo': <String>[
            'upload=1024; download=2048; total=107374182400; expire=0',
          ],
          'profile-title': <String>['Example panel'],
        },
      );
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(adapter),
        payloadMapper: testMapper,
      );

      final result = await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );
      final payload = result.valueOrNull!;

      expect(payload.body, contains('vless://'));
      expect(payload.profileTitle, equals('Example panel'));
      expect(payload.userInfo?.total, equals(107374182400));
      expect(payload.userInfo?.upload, equals(1024));
    });

    test('sends the honest User-Agent by default', () async {
      final adapter = StubHttpAdapter.text('vless://a@b:443#One');
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(adapter, userAgent: 'Commy/1.0.0'),
        payloadMapper: testMapper,
      );

      await fetcher.fetch(Fixtures.subscriptionUrl, throughTunnel: false);

      expect(
        adapter.requests.single.headers[HttpHeaders.userAgentHeader],
        equals('Commy/1.0.0'),
      );
    });

    test('an override replaces the User-Agent for that call only', () async {
      final adapter = StubHttpAdapter.text('vless://a@b:443#One');
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(adapter, userAgent: 'Commy/1.0.0'),
        payloadMapper: testMapper,
      );

      await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
        userAgent: CommyUserAgent.widelyAcceptedPreset,
      );

      expect(
        adapter.requests.single.headers[HttpHeaders.userAgentHeader],
        equals(CommyUserAgent.widelyAcceptedPreset),
      );
    });

    test('an empty body is malformed, not unreachable', () async {
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(StubHttpAdapter.text('   ')),
        payloadMapper: testMapper,
      );

      final result = await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    });

    test('a dead host becomes an unreachable failure', () async {
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(
          StubHttpAdapter.failing(DioExceptionType.connectionError),
        ),
        payloadMapper: testMapper,
      );

      final result = await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );
      final failure = result.failureOrNull;

      expect(failure, isA<SubscriptionUnreachableFailure>());
      expect(failure!.retryable, isTrue);
      expect(
        (failure as SubscriptionUnreachableFailure).cause,
        isA<HttpTransportError>(),
      );
    });

    test('a failure never prints the token', () async {
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(
          StubHttpAdapter.failing(DioExceptionType.connectionTimeout),
        ),
        payloadMapper: testMapper,
      );

      final result = await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(
        result.failureOrNull.toString(),
        isNot(contains('9f8e7d6c5b4a32100fedcba987654321')),
      );
    });

    test('a 404 is reported, not silently treated as an empty list', () async {
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(StubHttpAdapter.text('nope', statusCode: 404)),
        payloadMapper: testMapper,
      );

      final result = await fetcher.fetch(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      );

      expect(result.isErr, isTrue);
    });
  });

  group('CommyHttpClient', () {
    test('refuses a scheme that is not http or https', () async {
      final client = clientWith(StubHttpAdapter.text('x'));

      final result = await client.fetchText(
        Uri.parse('file:///etc/passwd'),
        throughTunnel: false,
      );

      expect(result.failureOrNull, isA<SubscriptionMalformedFailure>());
    });

    test('exposes every response header, lowercased', () async {
      final client = clientWith(
        StubHttpAdapter.text(
          'body',
          headers: <String, List<String>>{
            'Profile-Update-Interval': <String>['24'],
            'Profile-Web-Page-Url': <String>['https://panel.example.com/'],
          },
        ),
      );

      final response = (await client.fetchText(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      ))
          .valueOrNull!;

      expect(response.header('profile-update-interval'), equals('24'));
      expect(
        response.headerValues['profile-web-page-url'],
        equals('https://panel.example.com/'),
      );
    });

    test('a response never prints its body', () async {
      final client = clientWith(
        StubHttpAdapter.text('vless://${Fixtures.uuid}@h:443'),
      );

      final response = (await client.fetchText(
        Fixtures.subscriptionUrl,
        throughTunnel: false,
      ))
          .valueOrNull!;

      expect(response.toString(), isNot(contains(Fixtures.uuid)));
    });
  });
}
