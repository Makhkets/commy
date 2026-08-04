import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Version, core, licences — and the sentence that defines the product.
///
/// "Commy is not a VPN service" is on this screen because it is the one place
/// a user goes to find out what they installed. It is a constraint from
/// CLAUDE.md, not a slogan: no servers, no bundled configs, no accounts, no
/// backend.
class AboutScreen extends ConsumerWidget {
  /// Creates the screen.
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final info = ref.watch(appInfoProvider);
    final encryption = ref.watch(databaseEncryptionProvider);

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.about.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.settings),
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: spacing.s10),
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(spacing.s4),
            child: Container(
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: context.radii.lgAll,
              ),
              padding: EdgeInsets.all(spacing.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    t.app.name,
                    style: context.typography.title1.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: spacing.s2),
                  Text(
                    t.about.notAService,
                    style: context.typography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsSection(
            children: <Widget>[
              SettingsTile(
                icon: CommyIcons.info,
                title: t.about.version,
                value: info.fullVersion,
              ),
              SettingsTile(
                icon: CommyIcons.server,
                title: t.about.core,
                value: t.about.coreValue(version: info.coreVersion),
              ),
              SettingsTile(
                icon: CommyIcons.document,
                title: t.about.licences,
                value: t.about.licence,
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: t.app.name,
                  applicationVersion: info.fullVersion,
                ),
              ),
              SettingsTile(
                icon: CommyIcons.externalLink,
                title: t.about.sources,
                subtitle: AppInfo.repository.host,
                isMonospaceSubtitle: true,
                onTap: () => unawaited(_open(AppInfo.repository)),
              ),
            ],
          ),
          if (encryption != DatabaseEncryptionStatus.encrypted) ...<Widget>[
            SizedBox(height: spacing.s4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s4),
              child: ErrorBanner(
                message: t.about.storageDegraded,
                tone: CommyTone.info,
              ),
            ),
          ],
          SizedBox(height: spacing.s6),
        ],
      ),
    );
  }

  Future<void> _open(Uri url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
