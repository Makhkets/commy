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
          if (state.updatedExisting) ...<Widget>[
            SizedBox(height: spacing.s2),
            // Said rather than left to be noticed. Adding a panel the user
            // already has now refreshes the card they have instead of making a
            // second one, and without this line that reads as an import that
            // did nothing — the list is exactly as long as it was.
            Text(
              t.import.result.alreadyThere,
              style: context.typography.caption.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ],
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
          // The failure names its own action. Labelling the button off
          // `retryable` instead offered "close" for a storage error the
          // failure itself asks the user to retry, and sent the "show the
          // config" of an invalid configuration to the log tab.
          CommyButton(
            label: text.actionLabel,
            icon: text.action == FailureAction.retry
                ? CommyIcons.refresh
                : CommyIcons.diagnostics,
            onPressed: () => _act(context, ref, text),
          ),
          // Only where the action does not already land in diagnostics: two
          // buttons to the same screen are noise, not a second way out.
          if (text.needsLogRoute) ...<Widget>[
            SizedBox(height: spacing.s2),
            CommyButton(
              label: t.error.openLogs,
              variant: CommyButtonVariant.ghost,
              icon: CommyIcons.document,
              onPressed: () => _leaveFor(
                context,
                ref,
                FailureAction.openLogs.route!,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Does what [FailureText.action] declared.
  ///
  /// A retry stays in the sheet: popping would throw away the URL that was
  /// typed, which is the one thing a retry needs (docs/05-ux-flows.md,
  /// scenario 1). Clearing the failure hands the sheet its input back.
  void _act(BuildContext context, WidgetRef ref, FailureText text) {
    final route = text.action.route;
    if (route == null) {
      ref.read(importControllerProvider.notifier).reset();
      return;
    }
    _leaveFor(context, ref, route);
  }

  /// Clears the result and gets the sheet out of the way before navigating.
  ///
  /// The order matters: a sheet left open would sit on top of the very screen
  /// the user was just sent to, and a result left in the controller is the one
  /// the next open of the sheet would show instead of the import options.
  void _leaveFor(BuildContext context, WidgetRef ref, String route) {
    ref.read(importControllerProvider.notifier).reset();
    Navigator.of(context).pop();
    context.go(route);
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
