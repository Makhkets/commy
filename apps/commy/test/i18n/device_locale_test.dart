import 'dart:ui';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/device_locale.dart';
import 'package:commy_core/commy_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone in a language Commy has no strings for used to open it in
/// Russian — slang's base locale — while the notification beside it fell
/// back to English.
void main() {
  AppLocale resolve(List<String> tags) => DeviceLocale.resolve(<Locale>[
        for (final tag in tags) Locale(tag),
      ]);

  test('a Russian or an English phone gets its own language', () {
    expect(resolve(<String>['ru']), AppLocale.ru);
    expect(resolve(<String>['en']), AppLocale.en);
    expect(
      DeviceLocale.resolve(const <Locale>[Locale('en', 'GB')]),
      AppLocale.en,
    );
    expect(
      DeviceLocale.resolve(const <Locale>[Locale('ru', 'KZ')]),
      AppLocale.ru,
    );
  });

  test('a language Commy does not speak gets English, not Russian', () {
    for (final tag in <String>['de', 'fa', 'zh', 'tr', 'es', 'ar']) {
      expect(resolve(<String>[tag]), AppLocale.en, reason: tag);
    }
    expect(resolve(const <String>[]), AppLocale.en);
  });

  test("the user's own order decides between the two", () {
    // A Kazakh phone with Russian as its second language reads Russian.
    expect(resolve(<String>['kk', 'ru', 'en']), AppLocale.ru);
    expect(resolve(<String>['de', 'en', 'ru']), AppLocale.en);
    expect(resolve(<String>['uk', 'ru']), AppLocale.ru);
  });

  test('case does not matter', () {
    expect(resolve(<String>['RU']), AppLocale.ru);
  });

  group('adoptFromSystem', () {
    test("a pick in Android's own settings wins over the app's", () {
      expect(
        DeviceLocale.adoptFromSystem(chosen: 'ru', systemTag: 'en'),
        'en',
      );
      expect(DeviceLocale.adoptFromSystem(chosen: '', systemTag: 'ru'), 'ru');
      expect(
        DeviceLocale.adoptFromSystem(chosen: null, systemTag: 'EN'),
        'en',
      );
    });

    test('nothing to take over: none held, or the same as the app', () {
      expect(DeviceLocale.adoptFromSystem(chosen: 'ru', systemTag: ''), isNull);
      expect(
        DeviceLocale.adoptFromSystem(chosen: 'ru', systemTag: 'ru'),
        isNull,
      );
    });

    // "System default" picked in Android's settings over a mirrored choice.
    test('a cleared per-app language takes over "follow the system"', () {
      expect(
        DeviceLocale.adoptFromSystem(
          chosen: 'ru',
          systemTag: DeviceLocale.clearedSystemTag,
        ),
        '',
      );
      expect(
        DeviceLocale.adoptFromSystem(
          chosen: '',
          systemTag: DeviceLocale.clearedSystemTag,
        ),
        isNull,
      );
    });

    test('the cleared marker is the one the platform layer sends', () {
      expect(DeviceLocale.clearedSystemTag, SystemSettings.appLocaleCleared);
    });

    test('a language Commy has no strings for is not taken over', () {
      expect(
        DeviceLocale.adoptFromSystem(chosen: 'ru', systemTag: 'de'),
        isNull,
      );
    });
  });
}
