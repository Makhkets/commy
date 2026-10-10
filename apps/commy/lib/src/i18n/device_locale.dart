import 'dart:ui' show Locale;

import 'package:commy/gen/strings.g.dart';

/// Which of the app's languages a phone gets when the user left Appearance →
/// Language on "System".
///
/// slang's own `useDeviceLocale` answers a language it has no strings for
/// with the base locale, and the base locale is Russian: a phone in German,
/// Persian or Chinese opened Commy in Russian — a script most of those people
/// cannot read, on the first screen they ever see. The native strings
/// (`values/` is English, `values-ru/` Russian) already fell back to English,
/// so the notification and the app disagreed as well.
///
/// The phone's own list of languages is walked in the user's order: the first
/// one Commy speaks wins, so a Kazakh phone with Russian second in the list
/// still opens in Russian. A list with neither gets English — the language a
/// stranger is likeliest to read, and the one the README and store pages are
/// written in. Decided by the agent on the owner's standing delegation,
/// 2026-10-10 (docs/17, session 25).
abstract final class DeviceLocale {
  /// What the platform answers for "the user cleared the per-app language":
  /// `SystemSettings.appLocaleCleared`, repeated here so this file stays free
  /// of the platform package.
  static const String clearedSystemTag = 'system';

  /// The app language for a phone whose languages are [preferred], most
  /// preferred first.
  static AppLocale resolve(List<Locale> preferred) {
    for (final locale in preferred) {
      for (final candidate in AppLocale.values) {
        if (candidate.languageCode == locale.languageCode.toLowerCase()) {
          return candidate;
        }
      }
    }
    return AppLocale.en;
  }

  /// The language to take over from Android 13+'s own per-app setting
  /// (Settings → Apps → Commy → Language), or `null` to keep [chosen]. An
  /// empty string takes over "follow the system".
  ///
  /// The app mirrors its choice there, so the two only differ when the user
  /// picked a language in the system's settings — and then that pick wins,
  /// or the control Android shows would do nothing. [systemTag] is empty
  /// when the system holds none, and always below Android 13;
  /// [clearedSystemTag] when the user picked "System default" there over a
  /// language the app had mirrored. A language Commy has no strings for is
  /// not taken over.
  static String? adoptFromSystem({
    required String? chosen,
    required String systemTag,
  }) {
    if (systemTag == clearedSystemTag) {
      return (chosen ?? '').isEmpty ? null : '';
    }
    final wanted = systemTag.trim().toLowerCase();
    if (wanted.isEmpty || wanted == (chosen ?? '').toLowerCase()) {
      return null;
    }
    final speaks = AppLocale.values.any(
      (locale) => locale.languageCode == wanted,
    );
    return speaks ? wanted : null;
  }
}
