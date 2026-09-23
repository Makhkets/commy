import 'package:commy_core/commy_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `SystemSettings` against a mocked Kotlin side.
///
/// All three share one contract: they talk to the system, not to the tunnel,
/// and a missing platform is an answer — `false`, or an empty list — never an
/// exception.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel(WireChannels.method);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(method, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(method, null));

  group('setStartOnBoot', () {
    test('sends the flag as a bare boolean', () async {
      final ok = await const SystemSettings().setStartOnBoot(enabled: true);

      expect(ok, isTrue);
      expect(calls.single.method, WireMethods.setStartOnBoot);
      expect(calls.single.arguments, isTrue);
    });

    test('off is a call too, not an absence of one', () async {
      await const SystemSettings().setStartOnBoot(enabled: false);

      expect(calls.single.arguments, isFalse);
    });

    test('a platform without the receiver answers false and does not throw',
        () async {
      messenger.setMockMethodCallHandler(method, null);

      final ok = await const SystemSettings().setStartOnBoot(enabled: true);

      expect(ok, isFalse);
    });

    test('a platform error is swallowed into false', () async {
      messenger.setMockMethodCallHandler(method, (call) async {
        throw PlatformException(code: WireErrorCodes.unknown);
      });

      final ok = await const SystemSettings().setStartOnBoot(enabled: true);

      expect(ok, isFalse);
    });
  });

  group('ping', () {
    test('sends the host and the deadline, and reads the echo back',
        () async {
      messenger.setMockMethodCallHandler(method, (call) async {
        calls.add(call);
        return '{"delayMs":38}';
      });

      final delay = await const SystemSettings().ping(
        '45.151.180.167',
        timeout: const Duration(seconds: 5),
      );

      expect(delay, const Duration(milliseconds: 38));
      expect(calls.single.method, WireMethods.ping);
      expect(
        calls.single.arguments,
        '{"host":"45.151.180.167","timeoutMs":5000}',
      );
    });

    test('no echo is null, and so is a platform without the method',
        () async {
      messenger.setMockMethodCallHandler(
        method,
        (call) async => '{"delayMs":null}',
      );
      expect(
        await const SystemSettings()
            .ping('a.example', timeout: const Duration(seconds: 1)),
        isNull,
      );

      messenger.setMockMethodCallHandler(method, null);
      expect(
        await const SystemSettings()
            .ping('a.example', timeout: const Duration(seconds: 1)),
        isNull,
      );
    });
  });

  group('installedApps', () {
    void answer(String payload) {
      messenger.setMockMethodCallHandler(method, (call) async {
        calls.add(call);
        return payload;
      });
    }

    test('reads the entries off the wire', () async {
      answer(
        '[{"package": "org.mozilla.firefox", "label": "Firefox", '
        '"isSystem": false}]',
      );

      final apps = await const SystemSettings().installedApps();

      expect(calls.single.method, WireMethods.installedApps);
      expect(calls.single.arguments, isNull);
      expect(apps.single.packageName, 'org.mozilla.firefox');
      expect(apps.single.label, 'Firefox');
      expect(apps.single.isSystem, isFalse);
    });

    test('sorts by label, with the system apps last', () async {
      answer(
        '[${<String>[
          '{"package": "c.zebra", "label": "Zebra"}',
          '{"package": "c.system", "label": "Aaa system", "isSystem": true}',
          '{"package": "c.apple", "label": "apple"}',
        ].join(',')}]',
      );

      final apps = await const SystemSettings().installedApps();

      // Case-insensitive, and nobody scrolls past the system packages
      // looking for their browser.
      expect(
        apps.map((app) => app.packageName),
        <String>['c.apple', 'c.zebra', 'c.system'],
      );
    });

    test('a package with no label is named by its package', () async {
      answer('[{"package":"com.android.thing","label":""}]');

      final apps = await const SystemSettings().installedApps();

      expect(apps.single.label, 'com.android.thing');
    });

    test('an entry with no package at all is dropped', () async {
      answer('[{"label":"Nowhere"},{"package":"a.b","label":"Real"}]');

      final apps = await const SystemSettings().installedApps();

      expect(apps.map((app) => app.packageName), <String>['a.b']);
    });

    test('a platform that routes no apps answers with an empty list',
        () async {
      messenger.setMockMethodCallHandler(method, null);

      expect(await const SystemSettings().installedApps(), isEmpty);
    });

    test('a platform error is an empty list, not an exception', () async {
      messenger.setMockMethodCallHandler(method, (call) async {
        throw PlatformException(code: WireErrorCodes.unknown);
      });

      expect(await const SystemSettings().installedApps(), isEmpty);
    });
  });

  group('InstalledApp.matches', () {
    const app = InstalledApp(
      packageName: 'org.mozilla.firefox',
      label: 'Firefox',
    );

    test('finds by label and by package, either case', () {
      expect(app.matches('fire'), isTrue);
      expect(app.matches('FIRE'), isTrue);
      expect(app.matches('mozilla'), isTrue);
      expect(app.matches('chrome'), isFalse);
    });

    test('an empty query matches everything', () {
      expect(app.matches(''), isTrue);
      expect(app.matches('   '), isTrue);
    });
  });

  group('openVpnSettings', () {
    test('takes no argument', () async {
      final ok = await const SystemSettings().openVpnSettings();

      expect(ok, isTrue);
      expect(calls.single.method, WireMethods.openVpnSettings);
      expect(calls.single.arguments, isNull);
    });

    test('a platform without the screen answers false', () async {
      messenger.setMockMethodCallHandler(method, null);

      expect(await const SystemSettings().openVpnSettings(), isFalse);
    });
  });
}
