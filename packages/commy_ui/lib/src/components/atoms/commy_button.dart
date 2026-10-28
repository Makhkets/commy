import 'package:commy_ui/src/components/atoms/commy_button_variant.dart';
import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/components/commy_pressable.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The button of the system, in its four variants
/// (docs/04-design-system.md §8).
///
/// [label] is a finished, translated string: this package holds no text and
/// knows nothing about `slang`. The caller passes what the user reads — and
/// the verb on it names the result: "Connect", "Save copy", never "OK".
///
/// A press shows the instant a finger lands: the button shrinks to 97 % on a
/// spring ([CommyPressable]) and its fill darkens under the finger. The
/// corner is `control` (14) at every height.
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
    this.isLarge = false,
    this.semanticLabel,
    super.key,
  }) : assert(
          !(isCompact && isLarge),
          'A button is compact or large, not both.',
        );

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

  /// Whether this is the one main action of the screen, 52 dp tall.
  final bool isLarge;

  /// Overrides the label announced to assistive technology.
  final String? semanticLabel;

  /// Whether a tap will actually do something.
  bool get isEnabled => onPressed != null && !isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final shape = context.radii.controlAll;
    final foreground = _foreground(colors);
    final hasLeading = isLoading || icon != null;
    final minHeight = isCompact
        ? CommySizes.buttonHeightSmall
        : isLarge
            ? CommySizes.buttonHeightLarge
            : CommySizes.buttonHeight;
    // The dense variant keeps its 36 dp body and gains transparent margin up
    // to the minimum tap target, which still takes taps: "add rule", "open
    // logs" and the retry on a failed import sit at the ends of rows, where
    // the next thing to do is the small thing.
    final tapMargin = isCompact
        ? (CommySizes.minTapTarget - CommySizes.buttonHeightSmall) / 2
        : 0.0;

    // Focus is a ring on the button's own edge, never the InkWell's 12 %
    // overlay: on a black or a white fill that overlay moved by 1.02:1, and
    // a keyboard user tabbing onto "Add" could not see that it was there.
    final button = Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      child: CommyFocusable(
        onActivate: isEnabled ? onPressed : null,
        builder: (context, {required isFocused}) => CommyPressable(
          enabled: isEnabled,
          child: _HoverFill(
            idle: isCompact ? CommyColors.transparent : _background(colors),
            hovered: isEnabled && !isCompact ? _pressed(colors) : null,
            builder: (context, fill) => Material(
              // Compact draws its own fill below, inside the margin.
              color: fill,
              borderRadius: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isEnabled ? onPressed : null,
                canRequestFocus: false,
                borderRadius: shape,
                highlightColor: _pressedOverlay(colors),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: tapMargin),
                  child: Container(
                    constraints: BoxConstraints(minHeight: minHeight),
                    padding: EdgeInsets.symmetric(
                      horizontal: isCompact ? spacing.s3 : spacing.s4,
                      vertical: spacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: isCompact ? _background(colors) : null,
                      borderRadius: shape,
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: shape,
                      border: CommyFocusable.ring(colors, isFocused: isFocused),
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
                            style: (isCompact
                                    ? context.typography.captionStrong
                                    : context.typography.bodyStrong)
                                .copyWith(color: foreground),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
          : colors.fill;
    }
    return switch (variant) {
      CommyButtonVariant.primary => colors.accentSolid,
      CommyButtonVariant.secondary => colors.fill,
      CommyButtonVariant.ghost => CommyColors.transparent,
      CommyButtonVariant.danger => colors.statusErrorSolid,
    };
  }

  /// The fill under a pointer: only the primary needs its own, the others
  /// take the global hover wash.
  Color? _pressed(CommyColors colors) =>
      variant == CommyButtonVariant.primary ? colors.accentHover : null;

  /// What the fill turns into under a finger. On the primary — a black or a
  /// white — a grey overlay would vanish into it, so the press paints the
  /// pressed step of the action over it instead; elsewhere the theme's grey
  /// highlight is the press.
  Color? _pressedOverlay(CommyColors colors) => switch (variant) {
        CommyButtonVariant.primary => colors.accentHover,
        CommyButtonVariant.danger => colors.accentWash,
        CommyButtonVariant.secondary || CommyButtonVariant.ghost => null,
      };

  Color _foreground(CommyColors colors) {
    if (!isEnabled) {
      return colors.textDisabled;
    }
    return switch (variant) {
      CommyButtonVariant.primary => colors.accentOnSolid,
      CommyButtonVariant.secondary => colors.textPrimary,
      CommyButtonVariant.ghost => colors.textPrimary,
      CommyButtonVariant.danger => colors.statusErrorOnSolid,
    };
  }
}

/// Swaps a colour while a pointer is over the child.
///
/// A `MouseRegion` rather than `InkWell.onHover`, so that what changes is the
/// colour the surface is painted with rather than an overlay on top of it —
/// an overlay of the accent over the accent is exactly what was invisible.
/// On a touch device nothing ever enters, so nothing ever changes.
class _HoverFill extends StatefulWidget {
  const _HoverFill({
    required this.idle,
    required this.hovered,
    required this.builder,
  });

  /// The fill with no pointer over the child.
  final Color idle;

  /// The fill under a pointer, or `null` to keep [idle].
  final Color? hovered;

  /// Builds the child with whichever fill applies.
  final Widget Function(BuildContext context, Color fill) builder;

  @override
  State<_HoverFill> createState() => _HoverFillState();
}

class _HoverFillState extends State<_HoverFill> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final hovered = widget.hovered;
    if (hovered == null) {
      return widget.builder(context, widget.idle);
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: widget.builder(context, _over ? hovered : widget.idle),
    );
  }
}
