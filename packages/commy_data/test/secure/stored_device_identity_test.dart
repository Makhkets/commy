import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repositories/http_subscription_fetcher_test.dart'
    show clientWith, testMapper;
import '../support/fixtures.dart';
import '../support/stub_http_adapter.dart';

/// Settings held in memory: the identity reads one switch from them.
class _Settings implements SettingsRepository {
  _Settings(this.value);

  AppSettings value;

  @override
  Future<Result<AppSettings, CommyFailure>> read() async =>
      Ok<AppSettings, CommyFailure>(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String newId() => 'hwid-${++_next}';
}

/// A keystore that refuses every call, as one does on a wiped lock screen.
class _BrokenStore implements SecureStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('keystore unavailable');
}

void main() {
  late InMemorySecureStore store;
  late _Settings settings;

  StoredDeviceIdentity identity({SecureStore? over, String? model}) =>
      StoredDeviceIdentity(
        store: over ?? store,
        settings: settings,
        ids: _Ids(),
        platformName: 'Android',
        platformVersion: '15',
        deviceModel: model,
      );

  setUp(() {
    store = InMemorySecureStore();
    settings = _Settings(AppSettings.defaults);
  });

  group('StoredDeviceIdentity', () {
    test('sends the identifier and the platform, under the names panels read',
        () async {
      final headers = await identity(model: 'Pixel 6').subscriptionHeaders();

      expect(headers, <String, String>{
        'x-hwid': 'hwid-1',
        'x-device-os': 'Android',
        'x-ver-os': '15',
        'x-device-model': 'Pixel 6',
      });
    });

    test('a model that is not known is left out, not guessed', () async {
      final headers = await identity().subscriptionHeaders();

      expect(headers.containsKey('x-device-model'), isFalse);
      expect(headers['x-hwid'], 'hwid-1');
    });

    test('the identifier is made once and survives a new instance', () async {
      final first = await identity().subscriptionHeaders();
      final second = await identity().subscriptionHeaders();

      expect(second['x-hwid'], first['x-hwid']);
      expect(await store.read(SecretKeys.deviceId), 'hwid-1');
    });

    test('switched off, nothing is sent and nothing is even created', () async {
      settings.value = AppSettings.defaults.copyWith(sendDeviceId: false);

      expect(await identity().subscriptionHeaders(), isEmpty);
      expect(await store.contains(SecretKeys.deviceId), isFalse);
    });

    test('a reset forgets it, and the next request gets a new one', () async {
      final one = StoredDeviceIdentity(
        store: store,
        settings: settings,
        ids: _Ids().._next = 0,
        platformName: 'Android',
      );
      final before = (await one.subscriptionHeaders())['x-hwid'];

      expect((await one.reset()).isOk, isTrue);
      final after = (await one.subscriptionHeaders())['x-hwid'];

      expect(before, 'hwid-1');
      expect(after, 'hwid-2');
    });

    test('a keystore that refuses costs the headers, not the refresh',
        () async {
      final headers =
          await identity(over: _BrokenStore()).subscriptionHeaders();

      expect(headers, isEmpty);
    });
  });

  group('HttpSubscriptionFetcher with an identity', () {
    test('puts the headers on the subscription request', () async {
      final adapter = StubHttpAdapter.text('vless://a@b:443#One');
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(adapter),
        payloadMapper: testMapper,
        identity: identity(),
      );

      await fetcher.fetch(Fixtures.subscriptionUrl, throughTunnel: false);

      final sent = adapter.requests.single.headers;
      expect(sent['x-hwid'], 'hwid-1');
      expect(sent['x-device-os'], 'Android');
    });

    test('sends none of them once the user switched the identifier off',
        () async {
      settings.value = AppSettings.defaults.copyWith(sendDeviceId: false);
      final adapter = StubHttpAdapter.text('vless://a@b:443#One');
      final fetcher = HttpSubscriptionFetcher(
        client: clientWith(adapter),
        payloadMapper: testMapper,
        identity: identity(),
      );

      await fetcher.fetch(Fixtures.subscriptionUrl, throughTunnel: false);

      final sent = adapter.requests.single.headers;
      expect(sent.keys.where((key) => key.startsWith('x-')), isEmpty);
    });
  });
}
