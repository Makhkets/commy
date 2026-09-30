import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The fetcher the app actually wires, over a client that never opens a
/// socket.
///
/// Reading the body into servers is the use cases' job. The fetcher only
/// turns the headers into metadata, and what it hands on must be everything
/// the whole-response parser's payload was — that parser also read the body,
/// once more than anybody needed.
void main() {
  const body = 'vless://00000000-0000-4000-8000-000000000001@203.0.113.7:443'
      '?security=tls&sni=example.com#First\n'
      'trojan://secret@203.0.113.8:443?sni=example.com#Second\n';
  final response = HttpTextResponse(
    statusCode: 200,
    body: body,
    headers: const <String, List<String>>{
      'subscription-userinfo': <String>[
        'upload=100; download=200; total=1000; expire=1790000000',
      ],
      'profile-title': <String>['My panel'],
      'profile-update-interval': <String>['12'],
      'profile-web-page-url': <String>['https://panel.example/account'],
      'support-url': <String>['https://panel.example/support'],
      'announce': <String>['Maintenance tonight'],
    },
    url: Uri.parse('https://panel.example/sub/token'),
  );

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(_CannedHttpClient(response)),
        deviceIdentityProvider.overrideWithValue(const NoDeviceIdentity()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('the payload is the headers read and the body as it came', () async {
    final fetched = await container
        .read(subscriptionFetcherProvider)
        .fetch(response.url, throughTunnel: false);
    final payload = fetched.valueOrNull!;
    final before = SubscriptionResponseParser()
        .parse(body: body, headers: response.headerValues)
        .payload;

    expect(payload.body, same(body));
    expect(payload.profileTitle, equals('My panel'));
    expect(payload.profileTitle, equals(before.profileTitle));
    expect(payload.updateIntervalHours, equals(12));
    expect(payload.updateIntervalHours, equals(before.updateIntervalHours));
    expect(payload.profileWebPageUrl, equals(before.profileWebPageUrl));
    expect(payload.supportUrl, equals(before.supportUrl));
    expect(payload.announcement, equals('Maintenance tonight'));
    expect(payload.announcement, equals(before.announcement));
    expect(payload.userInfo?.upload, equals(100));
    expect(payload.userInfo?.download, equals(before.userInfo?.download));
    expect(payload.userInfo?.total, equals(before.userInfo?.total));
    expect(payload.userInfo?.expire, equals(before.userInfo?.expire));
  });
}

/// Answers every fetch with one response.
class _CannedHttpClient extends CommyHttpClient {
  /// Creates the client.
  _CannedHttpClient(this.response);

  /// The answer.
  final HttpTextResponse response;

  @override
  Future<Result<HttpTextResponse, CommyFailure>> fetchText(
    Uri url, {
    required bool throughTunnel,
    String? userAgentOverride,
    Map<String, String> extraHeaders = const <String, String>{},
    // Wider than dio's `CancelToken?`, which this package does not import.
    Object? cancelToken,
  }) async =>
      Ok<HttpTextResponse, CommyFailure>(response);
}

/// A device that sends no identifying headers.
class NoDeviceIdentity implements DeviceIdentity {
  /// Creates the identity.
  const NoDeviceIdentity();

  @override
  Future<Map<String, String>> subscriptionHeaders() async =>
      const <String, String>{};

  @override
  Future<Result<void, CommyFailure>> reset() async =>
      const Ok<void, CommyFailure>(null);
}
