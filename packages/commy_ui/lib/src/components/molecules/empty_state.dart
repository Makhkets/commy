import 'package:commy_ui/src/components/atoms/commy_button.dart';
import 'package:commy_ui/src/components/atoms/commy_button_variant.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The "nothing here yet" state of a screen.
///
/// One of the four states every screen owes the user — loading, empty, error,
/// success. An empty state without a next step is only half of one, which is
/// why [actionLabel] exists.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Lucide icon shown above the text, at 32.
  final IconData icon;

  /// Headline. Already translated.
  final String title;

  /// Explanatory paragraph. Already translated.
  final String? message;

  /// Label of the way out. Already translated.
  final String? actionLabel;

  /// Called when the way out is taken.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: CommySizes.iconEmpty,
              color: colors.textTertiary,
            ),
            SizedBox(height: spacing.s4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: type.title3.copyWith(color: colors.textPrimary),
            ),
            if (message != null) ...<Widget>[
              SizedBox(height: spacing.s2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
            ],
            if (actionLabel != null) ...<Widget>[
              SizedBox(height: spacing.s5),
              CommyButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: CommyButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
