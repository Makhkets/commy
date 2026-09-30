import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `Override` is not in flutter_riverpod's default export set.
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The language chosen in the app reaches the strings Android draws itself:
/// the tunnel notification, its channels, the Quick Settings tile. They used
/// to follow the system language whatever the app was set to.
void main() {
  late CommyTestHarness harness;
  late _RecordingSystemSettings system;
  late ProviderContainer container;

  void start({AppSettings settings = AppSettings.defaults}) {
    harness = CommyTestHarness(settings: settings);
    system = _RecordingSystemSettings();
    container = ProviderContainer(
      overrides: harness.overrides(
        extra: <Override>[systemSettingsProvider.overrideWithValue(system)],
      ),
    )..listen(nativeLocaleSyncProvider, (_, __) {});
  }

  tearDown(() async {
    container.dispose();
    await harness.dispose();
  });

  test('at launch the stored language is sent', () async {
    start(settings: const AppSettings(locale: 'ru'));
    await pumpEventQueue();

    expect(system.locales, <String>['ru']);
  });

  test('following the system is sent too, to clear an old choice', () async {
    // A reset or a restored backup can leave a tag on the other side that
    // the app no longer holds.
    start();
    await pumpEventQueue();

    expect(system.locales, <String>['']);
  });

  test('a change of language is sent once, and an unrelated write is not',
      () async {
    start(settings: const AppSettings(locale: 'ru'));
    await pumpEventQueue();
    final controller = container.read(settingsControllerProvider.notifier);

    await controller.setLocale('en');
    await pumpEventQueue();
    await controller.setThemeMode(AppThemeMode.dark);
    await pumpEventQueue();

    expect(system.locales, <String>['ru', 'en']);
  });
}

/// A `SystemSettings` that remembers what it was asked instead of calling
/// into a platform that is not there.
class _RecordingSystemSettings extends SystemSettings {
  _RecordingSystemSettings();

  /// Every tag handed to [setLocale], in order.
  final List<String> locales = <String>[];

  @override
  Future<bool> setLocale(String? tag) async {
    locales.add(tag ?? '');
    return true;
  }

  @override
  Future<bool> setStartOnBoot({required bool enabled}) async => true;
}
