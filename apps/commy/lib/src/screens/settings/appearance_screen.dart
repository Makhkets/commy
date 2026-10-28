import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/router/app_sections.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/widgets/async_section.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Theme, text size, motion and language.
///
/// The text size and "reduce motion" are what the design protocol asks every
/// interface to offer on its own (docs/04-design-system.md §11). Both sit on
/// top of the system's settings rather than replacing them: the size
/// multiplies the system's scale, and the app keeps still when either switch
/// says so. Every screen is still expected to survive 200 % of the system's
/// size — the control is a preference, not a way around a layout bug.
class AppearanceScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final settings = ref.watch(settingsProvider);

    return AdaptiveScaffold(
      destinations: AppSection.destinationsFor(t),
      selectedIndex: AppSection.settings.index,
      onDestinationSelected: (index) => AppSection.select(context, index),
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
              // One row, one announcement. The row carries the name and the
              // radio carries the state, and unmerged that is two nodes a
              // screen reader stops on: it read "Тёмная" as prose and then
              // "Тёмная, radio button, selected" beside it. Merged — and with
              // the radio no longer repeating a label the row already has —
              // it is what `RadioListTile` is: a name, a state, one stop.
              SettingsTile(
                title: _themeLabel(t, mode),
                selected: settings.themeMode == mode,
                trailing: CommyRadio<AppThemeMode>(
                  value: mode,
                  groupValue: settings.themeMode,
                  onChanged: (value) =>
                      unawaited(controller.setThemeMode(value)),
                ),
                onTap: () => unawaited(controller.setThemeMode(mode)),
              ),
          ],
        ),
        SectionLabel(t.appearance.textSize),
        SettingsSection(
          children: <Widget>[
            for (final size in AppTextSize.values)
              SettingsTile(
                title: _sizeLabel(t, size),
                selected: settings.textSize == size,
                trailing: CommyRadio<AppTextSize>(
                  value: size,
                  groupValue: settings.textSize,
                  onChanged: (value) =>
                      unawaited(controller.setTextSize(value)),
                ),
                onTap: () => unawaited(controller.setTextSize(size)),
              ),
          ],
        ),
        SectionLabel(t.appearance.motion),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              title: t.appearance.reduceMotion,
              subtitle: t.appearance.reduceMotionHint,
              trailing: CommySwitch(
                value: settings.reduceMotion,
                semanticLabel: t.appearance.reduceMotion,
                onChanged: (value) =>
                    unawaited(controller.setReduceMotion(enabled: value)),
              ),
            ),
          ],
        ),
        SectionLabel(t.appearance.language),
        SettingsSection(
          children: <Widget>[
            for (final locale in _locales)
              SettingsTile(
                title: _localeLabel(t, locale),
                selected: (settings.locale ?? '') == locale,
                trailing: CommyRadio<String>(
                  value: locale,
                  groupValue: settings.locale ?? '',
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

  String _sizeLabel(Translations t, AppTextSize size) => switch (size) {
        AppTextSize.small => t.appearance.textSmall,
        AppTextSize.medium => t.appearance.textMedium,
        AppTextSize.large => t.appearance.textLarge,
      };

  String _localeLabel(Translations t, String locale) => switch (locale) {
        'ru' => t.appearance.languageRu,
        'en' => t.appearance.languageEn,
        _ => t.appearance.languageSystem,
      };
}
