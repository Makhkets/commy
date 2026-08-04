import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_stack.dart';

void main() {
  late TestStack stack;
  late DriftSettingsRepository repository;

  setUp(() {
    stack = TestStack.create();
    repository = stack.settings;
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftSettingsRepository', () {
    test('an empty database reads the defaults', () async {
      final settings = (await repository.read()).valueOrNull;

      expect(settings, equals(AppSettings.defaults));
    });

    test('settings round trip', () async {
      const settings = AppSettings(
        themeMode: AppThemeMode.dark,
        locale: 'ru',
        killSwitch: true,
        autoConnect: true,
        logLevel: LogLevel.debug,
        mixedPort: 7890,
        tunStack: TunStack.mixed,
      );
      await repository.write(settings);

      expect((await repository.read()).valueOrNull, equals(settings));
    });

    test('watch emits the current settings', () async {
      await repository.write(
        const AppSettings(themeMode: AppThemeMode.light),
      );

      final emitted = await repository.watch().first;

      expect(emitted.themeMode, equals(AppThemeMode.light));
    });

    test('watch falls back to the defaults on a corrupted row', () async {
      await stack.database.customStatement(
        "INSERT INTO settings (key, value_json) VALUES ('app_settings', 'x')",
      );

      final emitted = await repository.watch().first;

      expect(emitted, equals(AppSettings.defaults));
    });

    test('the selected node id round trips', () async {
      await repository.writeSelectedNodeId('node-1');

      expect(
        (await repository.readSelectedNodeId()).valueOrNull,
        equals('node-1'),
      );
    });

    test('writing null clears the selection', () async {
      await repository.writeSelectedNodeId('node-1');
      await repository.writeSelectedNodeId(null);

      expect((await repository.readSelectedNodeId()).valueOrNull, isNull);
    });

    test('the ip check endpoint stays empty unless the user fills it',
        () async {
      // Exception E-1 to rule R1 is opt-in: nothing in this layer may put an
      // address there by itself.
      final settings = (await repository.read()).valueOrNull!;

      expect(settings.ipCheckUrl, isEmpty);
      expect(settings.isIpCheckEnabled, isFalse);
    });
  });
}
