import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/i18n/device_locale.dart';
import 'package:commy/src/router/app_router.dart';
import 'package:commy/src/state/app_visibility.dart';
import 'package:commy/src/state/failover_watchdog.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/rule_set_scheduler.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/state/subscription_scheduler.dart';
import 'package:commy/src/state/system_intent_listener.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/notice_host.dart';
import 'package:commy/src/widgets/toast_host.dart';
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

class _CommyAppState extends ConsumerState<CommyApp>
    with WidgetsBindingObserver {
  /// The last language applied, so an unrelated settings write does not
  /// reload a translation bundle for nothing.
  String? _appliedLocale;

  /// Tells the providers that poll only for the screen when there is none.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      onHide: () => ref.read(appVisibleProvider.notifier).hide(),
      onShow: () => ref.read(appVisibleProvider.notifier).show(),
    );
  }

  /// The phone's language changed while the app was open — Android's own
  /// settings, or the per-app language of Android 13+.
  ///
  /// A per-app pick made in the system's settings is taken over as the
  /// app's own choice (DeviceLocale.adoptFromSystem); otherwise only an app
  /// that follows the system follows the change, and a language picked in
  /// the app stays put.
  @override
  void didChangeLocales(List<Locale>? locales) {
    unawaited(_followSystemLocale());
  }

  Future<void> _followSystemLocale() async {
    final chosen = ref.read(settingsProvider).value?.locale;
    final system = await ref.read(systemSettingsProvider).appLocale();
    if (!mounted) {
      return;
    }
    final adopted = DeviceLocale.adoptFromSystem(
      chosen: chosen,
      systemTag: system,
    );
    if (adopted != null) {
      await ref.read(settingsControllerProvider.notifier).setLocale(adopted);
      return;
    }
    if (chosen == null || chosen.isEmpty) {
      await _applyLocale(chosen);
      // The strings Android draws — the notification channels, the launcher
      // shortcuts — follow the new system language too.
      await ref.read(systemSettingsProvider).setLocale('');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref
      // Long-lived subscriptions, watched from the root so they outlive every
      // screen.
      ..watch(logPumpProvider)
      // Listened to, not watched: kept awake the same way, but its value is a
      // new window every second while connected, and a watch rebuilt the
      // whole app shell — both themes included — on each one, for a value
      // this widget never reads.
      ..listen<TrafficWindow>(trafficHistoryProvider, (_, __) {})
      ..watch(trafficHistoryPumpProvider)
      // The `checking` step. It belongs to the connection, not to whichever
      // screen happens to be on top when the tunnel comes up.
      ..watch(autoCheckProvider)
      // Failover: a server that stops answering is swapped for a live one,
      // while the switch is on and a server was picked by hand.
      ..watch(failoverWatchdogProvider)
      // "Connect on launch", decided once off the first settled read.
      ..watch(autoConnectProvider)
      // Routing, DNS and settings edits reach a running core without a
      // reconnect. Made on one screen, applied whichever is on top.
      ..watch(liveReloadProvider)
      // "Connect on boot": the receiver in the manifest is made to agree
      // with the stored switch, once, the same way.
      ..watch(startOnBootSyncProvider)
      // The language chosen here, for the notification and the tile, which
      // Android draws without Flutter.
      ..watch(nativeLocaleSyncProvider)
      // The timer behind «авто 1 ч» on the subscription card. Rooted here
      // because a refresh falling due must not depend on the home screen
      // being the one on top.
      ..watch(subscriptionRefreshProvider)
      // Rule sets on disk, fetched again on the interval the user chose —
      // off unless they chose one (exceptions E-2 and E-3).
      ..watch(ruleSetRefreshProvider)
      // Deep links, opened files, shared text and the Quick Settings tile.
      ..watch(systemIntentProvider)
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
          // Toasts over the notices' host, so a notice raised anywhere —
          // and any toast a screen puts up — lands at the top of the window.
          builder: (context, child) => ToastHost(
            child: NoticeHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }

  Future<void> _applyLocale(String? locale) async {
    if (locale == null || locale.isEmpty) {
      // Not `useDeviceLocale`: for a language Commy has no strings for, it
      // answers Russian, the base locale (see [DeviceLocale]).
      await LocaleSettings.setLocale(
        DeviceLocale.resolve(
          WidgetsBinding.instance.platformDispatcher.locales,
        ),
      );
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
