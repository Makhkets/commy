import 'package:commy_core/commy_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CoreClientFactory', () {
    test('Android gets the real channel-backed client', () {
      final client = CoreClientFactory.create(
        platform: TargetPlatform.android,
      );

      expect(client, isA<AndroidCoreClient>());
    });

    test('every platform without a tunnel yet gets the fake', () {
      for (final platform in TargetPlatform.values) {
        if (platform == TargetPlatform.android) {
          continue;
        }
        final client = CoreClientFactory.create(platform: platform);
        addTearDown((client as FakeCoreClient).dispose);

        expect(
          client,
          isA<FakeCoreClient>(),
          reason: '$platform should fall back rather than throw',
        );
      }
    });

    test('never throws, so the app opens on a machine with no tunnel', () {
      for (final platform in TargetPlatform.values) {
        expect(
          () => CoreClientFactory.create(platform: platform),
          returnsNormally,
        );
      }
    });

    test('says out loud which platforms are real', () {
      expect(CoreClientFactory.supports(TargetPlatform.android), isTrue);
      expect(CoreClientFactory.supports(TargetPlatform.windows), isFalse);
      expect(CoreClientFactory.supports(TargetPlatform.iOS), isFalse);
    });

    test('notes the fallback in the log instead of failing silently', () {
      final logger = AppLogger(sink: (_) {});
      addTearDown(logger.dispose);

      final client = CoreClientFactory.create(
        logger: logger,
        platform: TargetPlatform.linux,
      );
      addTearDown((client as FakeCoreClient).dispose);

      expect(logger.buffer, isNotEmpty);
      expect(logger.buffer.single.message, contains('fake core'));
    });
  });
}
