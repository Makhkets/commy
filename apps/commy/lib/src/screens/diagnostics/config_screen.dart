import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The generated sing-box configuration, read only.
///
/// This is transparency as a feature, not a debug leftover: the user is
/// entitled to see exactly what was handed to the core. It goes through
/// `ConfigRedactor` first — the document holds a UUID and a password, and a
/// screen you can screenshot is not a place for either (rule R2, rule R3).
class ConfigScreen extends ConsumerWidget {
  /// Creates the screen.
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final config = ref.watch(tunnelControllerProvider).lastConfig;

    if (config == null) {
      return DiagnosticsShell(
        route: AppRoutes.diagnosticsConfig,
        child: EmptyState(
          icon: CommyIcons.document,
          title: t.diagnostics.configEmpty,
          message: t.diagnostics.configEmptyBody,
        ),
      );
    }

    final text = ConfigRedactor.export(config);

    return DiagnosticsShell(
      route: AppRoutes.diagnosticsConfig,
      actions: <Widget>[
        CommyIconButton(
          icon: CommyIcons.copy,
          semanticLabel: t.diagnostics.copy,
          tooltip: t.diagnostics.copy,
          onPressed: () =>
              unawaited(ref.read(clipboardProvider).write(text)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: Text(
              t.diagnostics.configRedacted,
              style: context.typography.caption.copyWith(
                color: colors.textTertiary,
              ),
            ),
          ),
          SizedBox(height: spacing.s3),
          Expanded(
            child: Container(
              margin: EdgeInsets.fromLTRB(
                spacing.s4,
                0,
                spacing.s4,
                spacing.s4,
              ),
              decoration: BoxDecoration(
                color: colors.bgInset,
                borderRadius: context.radii.mdAll,
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(spacing.s3),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    text,
                    style: context.typography.monoSmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
