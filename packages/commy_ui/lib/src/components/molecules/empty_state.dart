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
///
/// Centred while it fits, scrollable once it does not. It used to be a plain
/// centred column, which is fine on a 390pt phone at the system font size and
/// loses the bottom of itself on a 320pt one, or on any phone whose owner
/// turned the font up: at 1.15x the column already ran 45pt past the viewport
/// and the way out — the button that makes an empty state an empty state
/// rather than a dead end — was the part that went missing.
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

    final content = Padding(
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Nothing to scroll inside of, and nothing to overflow out of: a
        // caller that hands this an unbounded height is sizing to content
        // already, and a scroll view there would assert instead of helping.
        if (!constraints.hasBoundedHeight) {
          return Center(child: content);
        }
        return SingleChildScrollView(
          child: ConstrainedBox(
            // Fills the viewport when the content is shorter than it, so the
            // state stays optically centred rather than pinned to the top.
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
