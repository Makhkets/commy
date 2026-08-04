import 'package:commy_ui/src/components/atoms/commy_button_variant.dart';
import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The button of the system, in its four variants.
///
/// [label] is a finished, translated string: this package holds no text and
/// knows nothing about `slang`. The caller passes what the user reads.
class CommyButton extends StatelessWidget {
  /// Creates a button.
  const CommyButton({
    required this.label,
    required this.onPressed,
    this.variant = CommyButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.isCompact = false,
    this.semanticLabel,
    super.key,
  });

  /// Text on the button. Already translated.
  final String label;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Which role the button plays.
  final CommyButtonVariant variant;

  /// Optional leading Lucide icon.
  final IconData? icon;

  /// Whether the action is running. Replaces [icon] with a spinner and
  /// suppresses taps without changing the button's width.
  final bool isLoading;

  /// Whether the button stretches to the width of its parent.
  final bool isFullWidth;

  /// Whether to use the dense 36 dp height instead of 44 dp.
  final bool isCompact;

  /// Overrides the label announced to assistive technology.
  final String? semanticLabel;

  /// Whether a tap will actually do something.
  bool get isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final foreground = _foreground(colors);
    final border = _border(colors);
    final hasLeading = isLoading || icon != null;
    final minHeight = isCompact
        ? CommySizes.buttonHeightSmall
        : CommySizes.buttonHeight;

    final button = Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      child: Material(
        color: _background(colors),
        borderRadius: radii.smAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isEnabled ? onPressed : null,
          borderRadius: radii.smAll,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
              horizontal: spacing.s4,
              vertical: spacing.s2,
            ),
            decoration: BoxDecoration(
              borderRadius: radii.smAll,
              border: border == null ? null : Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (isLoading)
                  CommySpinner(
                    size: CommySizes.iconControl,
                    color: foreground,
                  )
                else if (icon != null)
                  Icon(
                    icon,
                    size: CommySizes.iconControl,
                    color: foreground,
                  ),
                if (hasLeading) SizedBox(width: spacing.s2),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: context.typography.bodyStrong.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!isFullWidth) {
      return button;
    }
    return SizedBox(width: double.infinity, child: button);
  }

  Color _background(CommyColors colors) {
    if (!isEnabled) {
      return variant == CommyButtonVariant.ghost
          ? CommyColors.transparent
          : colors.bgOverlay;
    }
    return switch (variant) {
      CommyButtonVariant.primary => colors.accentSolid,
      CommyButtonVariant.secondary => colors.bgOverlay,
      CommyButtonVariant.ghost => CommyColors.transparent,
      CommyButtonVariant.danger => colors.statusError,
    };
  }

  Color _foreground(CommyColors colors) {
    if (!isEnabled) {
      return colors.textDisabled;
    }
    return switch (variant) {
      CommyButtonVariant.primary => colors.accentOnSolid,
      CommyButtonVariant.secondary => colors.textPrimary,
      CommyButtonVariant.ghost => colors.textPrimary,
      CommyButtonVariant.danger => colors.textInverse,
    };
  }

  Color? _border(CommyColors colors) {
    if (variant != CommyButtonVariant.secondary) {
      return null;
    }
    return isEnabled ? colors.borderDefault : colors.borderSubtle;
  }
}
