import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/diagnostics/diagnostics_shell.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The generated sing-box configuration, read only.
///
/// This is transparency as a feature, not a debug leftover: the user is
/// entitled to see exactly what was handed to the core. It goes through
/// `ConfigRedactor` first — the document holds a UUID and a password, and a
/// screen you can screenshot is not a place for either (rule R2, rule R3).
///
/// It is also where "show the config" on a refused connect leads, so a
/// refusal outranks the last document that worked: the tab shows what was
/// refused and why, or — when the builder refused and there never was a
/// document — the reason alone.
class ConfigScreen extends ConsumerWidget {
  /// Creates the screen.
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final tunnel = ref.watch(tunnelControllerProvider);
    final refusal = switch (tunnel.failure) {
      final ConfigInvalidFailure failure => failure,
      _ => null,
    };
    final rejected = refusal == null ? null : tunnel.rejectedConfig;
    final config = rejected ?? tunnel.lastConfig;

    if (config == null) {
      return DiagnosticsShell(
        route: AppRoutes.diagnosticsConfig,
        // The connect-first empty state after a refused connect sent the user
        // back to the very button that had just failed. What the builder
        // objected to is the one thing this tab can still say.
        child: refusal == null
            ? EmptyState(
                icon: CommyIcons.document,
                title: t.diagnostics.configEmpty,
                message: t.diagnostics.configEmptyBody,
                actionLabel: t.diagnostics.goConnect,
                onAction: () => context.go(AppRoutes.home),
              )
            : EmptyState(
                icon: CommyIcons.warning,
                title: t.diagnostics.configNotBuilt,
                message: _reason(refusal, t),
                actionLabel: t.error.openLogs,
                onAction: () => context.go(AppRoutes.diagnosticsLogs),
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
          onPressed: () => unawaited(_copy(context, ref, text)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (refusal != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.s4,
                0,
                spacing.s4,
                spacing.s3,
              ),
              child: ErrorBanner(
                // Without a refused document the one below is the last that
                // worked — after a refused reload, still the one running —
                // so the headline says nothing was built rather than that
                // this document was refused.
                title: rejected == null
                    ? t.diagnostics.configNotBuilt
                    : t.diagnostics.configRefused,
                message: _reason(refusal, t),
              ),
            ),
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

  /// What was wrong with the document, in the words of whoever refused it.
  ///
  /// Redacted like a log line: a core's complaint can quote the field it
  /// choked on, and that field can be the credential (rule R3).
  static String _reason(ConfigInvalidFailure failure, Translations t) {
    final detail = const LogRedactor().redact(failure.detail).trim();
    return detail.isEmpty ? FailureText.of(failure, t).message : detail;
  }

  /// Copies the redacted document and says whether it landed.
  ///
  /// The write used to be fire-and-forget with no message at all, so the one
  /// button on this screen looked equally broken whether it had worked or
  /// not. Same toast as the log tab next door, for the same reason.
  Future<void> _copy(BuildContext context, WidgetRef ref, String text) async {
    final t = Translations.of(context);
    final result = await ref.read(clipboardProvider).write(text);
    if (!context.mounted) {
      return;
    }
    final failure = result.failureOrNull;
    ToastMessenger.show(
      context,
      message: failure == null
          ? t.diagnostics.copied
          : FailureText.of(failure, t).message,
      tone: failure == null ? CommyTone.info : CommyTone.error,
      icon: failure == null ? CommyIcons.copy : CommyIcons.warning,
    );
  }
}
