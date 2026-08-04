import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the import sheet shows once an import has run.
///
/// Three outcomes, and each one has to be actionable:
///
/// * servers came in — say how many, name the skipped ones, and get out of the
///   way;
/// * nothing parsed — that is not an error, it is an empty result, and it says
///   what a valid input looks like;
/// * the import failed — cause, action, route to the logs.
class ImportResultPanel extends ConsumerWidget {
  /// Creates the panel.
  const ImportResultPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final state = ref.watch(importControllerProvider);
    final failure = state.failure;

    if (failure != null) {
      return _FailurePanel(failure: failure);
    }

    final outcome = state.outcome ?? ParseOutcome.empty;
    if (!outcome.hasNodes) {
      return Padding(
        padding: EdgeInsets.all(spacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            EmptyState(
              icon: CommyIcons.empty,
              title: t.import.result.nothing,
              message: t.import.result.nothingBody,
            ),
            SizedBox(height: spacing.s4),
            CommyButton(
              label: t.common.close,
              variant: CommyButtonVariant.secondary,
              onPressed: () => _close(context, ref),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.all(spacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                CommyIcons.success,
                size: CommySizes.iconControl,
                color: context.colors.statusConnected,
              ),
              SizedBox(width: spacing.s2),
              Expanded(
                child: Text(
                  t.import.result.imported(count: outcome.nodes.length),
                  style: context.typography.title3.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (outcome.hasFailures) ...<Widget>[
            SizedBox(height: spacing.s3),
            _SkippedLines(failures: outcome.failures),
          ],
          SizedBox(height: spacing.s5),
          CommyButton(
            label: t.common.done,
            onPressed: () => _close(context, ref),
          ),
        ],
      ),
    );
  }

  void _close(BuildContext context, WidgetRef ref) {
    ref.read(importControllerProvider.notifier).reset();
    Navigator.of(context).pop();
  }
}

class _FailurePanel extends ConsumerWidget {
  const _FailurePanel({required this.failure});

  final CommyFailure failure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final text = FailureText.of(failure, t);

    return Padding(
      padding: EdgeInsets.all(spacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ErrorBanner(message: text.message, title: t.error.title),
          SizedBox(height: spacing.s4),
          CommyButton(
            label: text.retryable ? t.common.retry : t.common.close,
            onPressed: () {
              ref.read(importControllerProvider.notifier).reset();
              if (!text.retryable) {
                Navigator.of(context).pop();
              }
            },
          ),
          SizedBox(height: spacing.s2),
          CommyButton(
            label: t.error.openLogs,
            variant: CommyButtonVariant.ghost,
            icon: CommyIcons.document,
            onPressed: () {
              ref.read(importControllerProvider.notifier).reset();
              Navigator.of(context).pop();
              context.go(FailureAction.openLogs.route!);
            },
          ),
        ],
      ),
    );
  }
}

/// The "3 skipped" line, expandable into the reasons.
///
/// The lines shown are [ImportFailure.redactedLine], never the raw input: a
/// broken link still carries a password.
class _SkippedLines extends StatefulWidget {
  const _SkippedLines({required this.failures});

  final List<ImportFailure> failures;

  @override
  State<_SkippedLines> createState() => _SkippedLinesState();
}

class _SkippedLinesState extends State<_SkippedLines> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                t.import.result.skipped(count: widget.failures.length),
                style: context.typography.caption.copyWith(
                  color: colors.statusConnecting,
                ),
              ),
            ),
            CommyButton(
              label: t.import.result.showSkipped,
              variant: CommyButtonVariant.ghost,
              isCompact: true,
              icon: _expanded ? CommyIcons.chevronUp : CommyIcons.chevronDown,
              onPressed: () => setState(() => _expanded = !_expanded),
            ),
          ],
        ),
        if (_expanded) ...<Widget>[
          SizedBox(height: spacing.s2),
          for (final failure in widget.failures)
            Padding(
              padding: EdgeInsets.only(bottom: spacing.s2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    failure.redactedLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typography.monoSmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    failure.reason,
                    style: context.typography.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
