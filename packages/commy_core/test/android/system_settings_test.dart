import 'package:commy_core/commy_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives `SystemSettings` against a mocked Kotlin side.
///
/// Both methods share one contract: they talk to the system, not to the
/// tunnel, and a missing platform is an answer (`false`), never an exception.
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
