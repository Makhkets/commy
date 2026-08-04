import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Theme and language.
///
/// Text size is not here. It is the system setting, and every screen in the
/// app is expected to survive 200% of it — duplicating the control would
/// invite people to fix a layout bug by shrinking the text.
class AppearanceScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final settings = ref.watch(settingsProvider);

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.appearance.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.settings),
      ),
      body: AsyncSection<AppSettings>(
        value: settings,
        skeleton: const ListSkeleton(rows: 5, hasHeader: true),
        onRetry: () => ref.invalidate(settingsProvider),
        builder: (context, value) => _Body(settings: value),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final controller = ref.read(settingsControllerProvider.notifier);

    return ListView(
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        SectionLabel(t.appearance.theme),
        SettingsSection(
          children: <Widget>[
            for (final mode in AppThemeMode.values)
              SettingsTile(
                title: _themeLabel(t, mode),
                trailing: CommyRadio<AppThemeMode>(
                  value: mode,
                  groupValue: settings.themeMode,
                  semanticLabel: _themeLabel(t, mode),
                  onChanged: (value) =>
                      unawaited(controller.setThemeMode(value)),
                ),
                onTap: () => unawaited(controller.setThemeMode(mode)),
              ),
          ],
        ),
        SectionLabel(t.appearance.language),
        SettingsSection(
          children: <Widget>[
            for (final locale in _locales)
              SettingsTile(
                title: _localeLabel(t, locale),
                trailing: CommyRadio<String>(
                  value: locale,
                  groupValue: settings.locale ?? '',
                  semanticLabel: _localeLabel(t, locale),
                  onChanged: (value) => unawaited(controller.setLocale(value)),
                ),
                onTap: () => unawaited(controller.setLocale(locale)),
              ),
          ],
        ),
        SizedBox(height: spacing.s6),
      ],
    );
  }

  /// The empty string is "follow the system", which is what
  /// `AppSettings.copyWith` turns back into `null`.
  static const List<String> _locales = <String>['', 'ru', 'en'];

  String _themeLabel(Translations t, AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => t.appearance.themeSystem,
        AppThemeMode.light => t.appearance.themeLight,
        AppThemeMode.dark => t.appearance.themeDark,
      };

  String _localeLabel(Translations t, String locale) => switch (locale) {
        'ru' => t.appearance.languageRu,
        'en' => t.appearance.languageEn,
        _ => t.appearance.languageSystem,
      };
}
