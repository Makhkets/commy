import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_router.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The root widget.
///
/// Three things are wired here and nowhere else:
///
/// * both themes, straight from `commy_ui` — the app itself picks no colour
///   (rule R4);
/// * the language, which follows the stored setting and falls back to the
///   device;
/// * two long-lived subscriptions — the log pump and the traffic window — that
///   have to keep running whatever screen is on top. Watching them from a
///   screen would mean the log stops recording the moment you leave it.
class CommyApp extends ConsumerStatefulWidget {
  /// Creates the app.
  const CommyApp({super.key});

  @override
  ConsumerState<CommyApp> createState() => _CommyAppState();
}

class _CommyAppState extends ConsumerState<CommyApp> {
  /// The last language applied, so an unrelated settings write does not
  /// reload a translation bundle for nothing.
  String? _appliedLocale;

  @override
  Widget build(BuildContext context) {
    ref
      // Two long-lived subscriptions, watched from the root so they outlive
      // every screen.
      ..watch(logPumpProvider)
      ..watch(trafficHistoryProvider)
      // Loading a locale is asynchronous — slang defers every non-base
      // bundle — so it happens in a listener rather than during build.
      ..listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
        final locale = next.value?.locale;
        if (locale != _appliedLocale) {
          _appliedLocale = locale;
          unawaited(_applyLocale(locale));
        }
      });

    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;


    return TranslationProvider(
      child: Builder(
        builder: (context) => MaterialApp.router(
          onGenerateTitle: (context) => Translations.of(context).app.name,
          debugShowCheckedModeBanner: false,
          theme: CommyTheme.light,
          darkTheme: CommyTheme.dark,
          themeMode: _themeModeOf(settings.themeMode),
          routerConfig: router,
          locale: TranslationProvider.of(context).flutterLocale,
          supportedLocales: AppLocaleUtils.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
        ),
      ),
    );
  }

  Future<void> _applyLocale(String? locale) async {
    if (locale == null || locale.isEmpty) {
      await LocaleSettings.useDeviceLocale();
      return;
    }
    await LocaleSettings.setLocaleRaw(locale);
  }

  ThemeMode _themeModeOf(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };
}
