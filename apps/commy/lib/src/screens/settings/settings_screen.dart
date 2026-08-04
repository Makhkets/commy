import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
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

/// Settings: the four sections, the network-silence panel, and connection.
///
/// The silence panel is not decoration and not marketing. Rule R1 says the
/// list of outgoing requests is closed; this screen is where that list is
/// visible and switchable, and the closing line says a fourth entry cannot
/// appear without changing this screen. Layout follows
/// docs/design-refs/08-settings.png.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final settings = ref.watch(settingsProvider);
    final routing = ref.watch(routingPolicyProvider).value;

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.settings.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.home),
      ),
      body: AsyncSection<AppSettings>(
        value: settings,
        skeleton: const ListSkeleton(rows: 6, hasHeader: true),
        onRetry: () => ref.invalidate(settingsProvider),
        builder: (context, value) => _Body(settings: value, routing: routing),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings, required this.routing});

  final AppSettings settings;
  final RoutingPolicy? routing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final controller = ref.read(settingsControllerProvider.notifier);

    return ListView(
      padding: EdgeInsets.only(bottom: spacing.s10),
      children: <Widget>[
        SectionLabel(t.settings.sections),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.routing,
              title: t.settings.routing,
              subtitle: _routingSubtitle(t),
              onTap: () => context.go(AppRoutes.routing),
            ),
            SettingsTile(
              icon: CommyIcons.diagnostics,
              title: t.settings.diagnostics,
              subtitle: t.settings.diagnosticsSubtitle,
              onTap: () => context.go(AppRoutes.diagnosticsLogs),
            ),
            SettingsTile(
              icon: CommyIcons.settings,
              title: t.settings.appearance,
              subtitle: t.settings.appearanceSubtitle,
              onTap: () => context.go(AppRoutes.appearance),
            ),
            SettingsTile(
              icon: CommyIcons.info,
              title: t.settings.about,
              subtitle: t.settings.aboutSubtitle,
              onTap: () => context.go(AppRoutes.about),
            ),
          ],
        ),
        SizedBox(height: spacing.s5),
        _SilencePanel(settings: settings),
        SectionLabel(t.settings.connection.title),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.power,
              title: t.settings.connection.autoConnect,
              subtitle: t.settings.connection.autoConnectHint,
              trailing: CommySwitch(
                value: settings.autoConnect,
                semanticLabel: t.settings.connection.autoConnect,
                onChanged: (value) => unawaited(
                  controller.save(settings.copyWith(autoConnect: value)),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.clock,
              title: t.settings.connection.startOnBoot,
              subtitle: t.settings.connection.startOnBootHint,
              trailing: CommySwitch(
                value: settings.startOnBoot,
                semanticLabel: t.settings.connection.startOnBoot,
                onChanged: (value) => unawaited(
                  controller.save(settings.copyWith(startOnBoot: value)),
                ),
              ),
            ),
            // Not a switch. Blocking traffic when the tunnel dies is a promise
            // this process cannot keep — a killed process blocks nothing — so
            // the row names the mechanism that can keep it, says it belongs to
            // the system, and opens it.
            SettingsTile(
              icon: CommyIcons.block,
              title: t.settings.connection.killSwitch,
              subtitle: t.settings.connection.killSwitchHint,
              onTap: () => unawaited(_openVpnSettings(context, ref)),
            ),
            SettingsTile(
              icon: CommyIcons.offline,
              title: t.settings.connection.hideUnavailable,
              subtitle: t.settings.connection.hideUnavailableHint,
              trailing: CommySwitch(
                value: settings.hideUnavailable,
                semanticLabel: t.settings.connection.hideUnavailable,
                onChanged: (value) => unawaited(
                  controller.save(settings.copyWith(hideUnavailable: value)),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.globe,
              title: t.settings.connection.allowLan,
              subtitle: t.settings.connection.allowLanHint,
              trailing: CommySwitch(
                value: settings.allowLan,
                semanticLabel: t.settings.connection.allowLan,
                onChanged: (value) => unawaited(
                  controller.save(settings.copyWith(allowLan: value)),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.s6),
      ],
    );
  }

  /// Opens the system VPN settings, or explains that this build has none.
  ///
  /// Desktop and the occasional Android image have no such screen. Saying so
  /// is better than a row that swallows the tap.
  Future<void> _openVpnSettings(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await ref.read(systemSettingsProvider).openVpnSettings();
    if (opened || messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          content: Toast(
            message: t.settings.connection.killSwitchUnavailable,
            tone: CommyTone.info,
            icon: CommyIcons.info,
          ),
        ),
      );
  }

  String _routingSubtitle(Translations t) {
    final policy = routing;
    if (policy == null) {
      return t.settings.routingSubtitle;
    }
    final mode = switch (policy.mode) {
      RoutingMode.global => t.routing.mode.global,
      RoutingMode.rules => t.routing.mode.rules,
      RoutingMode.direct => t.routing.mode.direct,
    };
    return '$mode · ${t.routing.rules}: ${policy.rules.length}';
  }
}

/// The closed list of outgoing requests, with a switch on each.
class _SilencePanel extends ConsumerWidget {
  const _SilencePanel({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final routing = ref.watch(routingPolicyProvider).value;
    final controller = ref.read(settingsControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: Container(
            decoration: BoxDecoration(
              color: colors.statusConnectedWash,
              borderRadius: context.radii.lgAll,
            ),
            padding: EdgeInsets.all(spacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      CommyIcons.proxy,
                      size: CommySizes.iconControl,
                      color: colors.statusConnected,
                    ),
                    SizedBox(width: spacing.s2),
                    Text(
                      t.settings.silence.title,
                      style: context.typography.title3.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.s2),
                Text(
                  t.settings.silence.body,
                  style: context.typography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: spacing.s3),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.globe,
              title: t.settings.silence.ipCheck,
              subtitle: t.settings.silence.ipCheckHint,
              isMonospaceSubtitle: true,
              trailing: CommySwitch(
                value: settings.isIpCheckEnabled,
                semanticLabel: t.settings.silence.ipCheck,
                onChanged: (value) => unawaited(
                  controller.setIpCheck(enabled: value),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.routing,
              title: t.settings.silence.ruleSets,
              subtitle: t.settings.silence.ruleSetsHint,
              isMonospaceSubtitle: true,
              trailing: CommySwitch(
                value: routing?.mode == RoutingMode.rules,
                semanticLabel: t.settings.silence.ruleSets,
                onChanged: (value) => unawaited(
                  controller.setRuleSetsEnabled(enabled: value),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.block,
              title: t.settings.silence.blockLists,
              subtitle: t.settings.silence.blockListsHint,
              isMonospaceSubtitle: true,
              trailing: CommySwitch(
                value: routing?.blockAds ?? false,
                semanticLabel: t.settings.silence.blockLists,
                onChanged: (value) => unawaited(
                  controller.setBlockAds(enabled: value),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            spacing.s4,
            spacing.s2,
            spacing.s4,
            0,
          ),
          child: Text(
            t.settings.silence.footer,
            style: context.typography.caption.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}
