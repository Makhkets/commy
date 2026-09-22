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
    final minHeight =
        isCompact ? CommySizes.buttonHeightSmall : CommySizes.buttonHeight;
    // The dense variant keeps its 36pt pill and gains transparent margin up
    // to the minimum tap target, which still takes taps — the idiom
    // `CheckButton` and `CommyChip` already use. It was the last control in
    // the app under that floor: "add rule", "open logs", "grant permission"
    // and the retry on a failed import are all this button, all on screens
    // where the next thing to do is the small thing at the end of a row.
    //
    // The regular 44pt button is left alone. 44 is its own token, matches
    // what iOS asks for, and every one of them would move by 4pt.
    final tapMargin = isCompact
        ? (CommySizes.minTapTarget - CommySizes.buttonHeightSmall) / 2
        : 0.0;

    // What the fill becomes under a pointer, or `null` where it does not
    // change. Only the primary variant needs saying: its fill is
    // `accentSolid`, a near-white, and the global hover overlay is
    // `accentWash` — eight percent of that same near-white, which on top of
    // it moved exactly one pixel in a measured frame. `accentHover` exists
    // for this and was referenced nowhere in the app. The ghost and the
    // secondary variants sit on a transparent or a dark fill, where the
    // overlay is plainly visible, and they are left alone.
    final hoverFill =
        variant == CommyButtonVariant.primary && isEnabled && !isCompact
            ? colors.accentHover
            : null;

    final button = Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      child: _HoverFill(
        idle: isCompact ? CommyColors.transparent : _background(colors),
        hovered: hoverFill,
        builder: (context, fill) => Material(
          // Compact draws its own fill below, inside the margin; anything
          // else keeps painting it here.
          color: fill,
          borderRadius: radii.smAll,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isEnabled ? onPressed : null,
            borderRadius: radii.smAll,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: tapMargin),
              child: Container(
                constraints: BoxConstraints(minHeight: minHeight),
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.s4,
                  vertical: spacing.s2,
                ),
                decoration: BoxDecoration(
                  color: isCompact ? _background(colors) : null,
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
