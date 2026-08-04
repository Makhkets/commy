import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A failure filling a whole screen: cause, action, and a way to the logs.
///
/// The three parts are not decoration. docs/05-ux-flows.md defines the error
/// state of every screen as "причина человеческим языком + действие + путь к
/// логам", and this widget is the only place that shape is spelled out, so a
/// screen cannot accidentally ship two of the three.
class FailureView extends StatelessWidget {
  /// Creates the view.
  const FailureView({required this.failure, this.onRetry, super.key});

  /// What went wrong.
  final CommyFailure failure;

  /// Called when the primary action is "try the same thing again".
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = FailureText.of(failure, t);
    final spacing = context.spacing;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(spacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            EmptyState(
              icon: CommyIcons.error,
              title: t.error.title,
              message: text.message,
            ),
            SizedBox(height: spacing.s4),
            CommyButton(
              label: text.actionLabel,
              onPressed: () => _act(context, text),
              icon: text.action == FailureAction.retry
                  ? CommyIcons.refresh
                  : CommyIcons.diagnostics,
            ),
            if (text.needsLogRoute) ...<Widget>[
              SizedBox(height: spacing.s2),
              CommyButton(
                label: t.error.openLogs,
                variant: CommyButtonVariant.ghost,
                onPressed: () => context.go(FailureAction.openLogs.route!),
                icon: CommyIcons.document,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _act(BuildContext context, FailureText text) {
    final route = text.action.route;
    if (route == null) {
      onRetry?.call();
      return;
    }
    context.go(route);
  }
}

/// The same failure as a banner above content that is still worth showing.
///
/// The home screen uses this: a tunnel that failed to come up does not make
/// the server list useless, so the list stays and the reason sits above it
/// (docs/design-refs/06-home-error.png).
class FailureBanner extends StatelessWidget {
  /// Creates the banner.
  const FailureBanner({
    required this.failure,
    this.onRetry,
    this.onDismiss,
    super.key,
  });

  /// What went wrong.
  final CommyFailure failure;

  /// Called when the primary action is "try the same thing again".
  final VoidCallback? onRetry;

  /// Called when the user closes the banner.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final text = FailureText.of(failure, t);
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ErrorBanner(
            message: text.message,
            actionLabel: text.actionLabel,
            onAction: () => _act(context, text),
            onDismiss: onDismiss,
            dismissSemanticLabel: t.a11y.dismiss,
          ),
          if (text.needsLogRoute) ...<Widget>[
            SizedBox(height: spacing.s2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: CommyButton(
                label: t.error.openLogs,
                variant: CommyButtonVariant.ghost,
                isCompact: true,
                icon: CommyIcons.document,
                onPressed: () => context.go(FailureAction.openLogs.route!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _act(BuildContext context, FailureText text) {
    final route = text.action.route;
    if (route == null) {
      onRetry?.call();
      return;
    }
    context.go(route);
  }
}
