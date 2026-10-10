import 'package:commy/app.dart';
import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/system_intent_listener.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod's default export set.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The language wiring inside `CommyApp`: a phone in a language Commy does
/// not speak gets English, a change of the phone's language reaches an app
/// that follows the system, a language chosen in the app stays put — unless
/// it was changed in Android 13+'s own per-app setting.
void main() {
  late CommyTestHarness harness;
  late _LocaleSystem system;

  Future<void> pumpApp(WidgetTester tester, {String? stored}) async {
    harness = CommyTestHarness(
      nodes: <ProxyNode>[testNode()],
      settings: AppSettings(locale: stored),
    );
    addTearDown(harness.dispose);
    system = _LocaleSystem();
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(() => LocaleSettings.setLocale(AppLocale.ru));
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides(
          extra: <Override>[
            systemSettingsProvider.overrideWithValue(system),
            systemIntentsProvider.overrideWithValue(const _NoIntents()),
          ],
        ),
        child: const CommyApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> phoneSpeaks(WidgetTester tester, String language) async {
    tester.platformDispatcher.localesTestValue = <Locale>[Locale(language)];
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('following the system, a German phone gets English',
      (tester) async {
    await pumpApp(tester);

    await phoneSpeaks(tester, 'de');

    expect(LocaleSettings.currentLocale, AppLocale.en);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
  });

  testWidgets('following the system, a change of language is followed',
      (tester) async {
    await pumpApp(tester);

    await phoneSpeaks(tester, 'en');
    await phoneSpeaks(tester, 'ru');

    expect(LocaleSettings.currentLocale, AppLocale.ru);
  });

  testWidgets('a language chosen in the app stays put', (tester) async {
    await pumpApp(tester, stored: 'ru');

    await phoneSpeaks(tester, 'en');

    expect(LocaleSettings.currentLocale, AppLocale.ru);
  });

  testWidgets("a pick in Android's per-app setting is taken over",
      (tester) async {
    await pumpApp(tester, stored: 'ru');
    system.systemTag = 'en';

    // What Android does after a per-app pick: the app's locale changes.
    await phoneSpeaks(tester, 'en');

    final stored = await harness.settingsRepository.read();
    expect(stored.valueOrNull?.locale, 'en');
    expect(LocaleSettings.currentLocale, AppLocale.en);
  });
}

/// A platform that answers the per-app language question and nothing else.
class _LocaleSystem extends SystemSettings {
  _LocaleSystem();

  /// What [appLocale] answers.
  String systemTag = '';

  @override
  Future<String> appLocale() async => systemTag;

  @override
  Future<bool> setLocale(String? tag) async => true;

  @override
  Future<bool> setStartOnBoot({required bool enabled}) async => true;

  @override
  Future<DeviceDescription?> deviceInfo() async => null;
}

/// Nothing handed over from outside the app.
class _NoIntents implements SystemIntents {
  const _NoIntents();

  @override
  Stream<SystemIntent> get events => const Stream<SystemIntent>.empty();
}
