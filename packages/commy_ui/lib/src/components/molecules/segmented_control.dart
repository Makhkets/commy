import 'package:commy_ui/src/components/molecules/segmented_control_item.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A row of mutually exclusive options sharing one recessed track.
///
/// Used for the routing mode — global, rules, direct — where the three
/// choices have to be visible at once because the difference between them is
/// the whole point of the screen.
///
/// Segments share the track in proportion to how wide their labels actually
/// are, not in equal slices. Equal slices look tidy with labels of one
/// length and fail with real ones: four Russian diagnostics tabs on a 390pt
/// phone gave every segment the same 87pt, which is room to spare for
/// "Логи" and not enough for "Соединения" — so the two words a person
/// needs to tell apart both arrived as an ellipsis. Proportional shares fit
/// all four, and when the labels genuinely cannot fit they shorten by the
/// same ratio instead of the same number of pixels.
class SegmentedControl<T> extends StatelessWidget {
  /// Creates a segmented control.
  const SegmentedControl({
    required this.segments,
    required this.value,
    required this.onChanged,
    super.key,
  }) : assert(segments.length > 1, 'a segmented control needs two options');

  /// The options, in the order they are shown.
  final List<SegmentedControlItem<T>> segments;

  /// The currently selected value.
  final T value;

  /// Called with the newly selected value. `null` disables the control.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgInset,
        borderRadius: context.radii.smAll,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Padding(
        padding: EdgeInsets.all(spacing.s1),
        child: Row(
          children: <Widget>[
            for (final segment in segments)
              Expanded(
                flex: _widthOf(context, segment),
                child: _Segment<T>(
                  segment: segment,
                  isSelected: segment.value == value,
                  onTap: onChanged == null
                      ? null
                      : () => onChanged!(segment.value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What one segment needs, in whole logical pixels, to show its label.
  ///
  /// Used as the flex weight, so a track wider than the sum of these gives
  /// every segment more room than it asked for and nothing is ellipsized.
  /// Measured with the same style, scaler and direction the label is drawn
  /// with, and padded exactly as [_Segment] pads it.
  int _widthOf(BuildContext context, SegmentedControlItem<T> segment) {
    final painter = TextPainter(
      text: TextSpan(
        text: segment.label,
        style: context.typography.captionStrong,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    var width = painter.width;
    painter.dispose();
    if (segment.icon != null) {
      width += CommySizes.iconInline + context.spacing.s1;
    }
    width += context.spacing.s2 * 2;
    // A weight has to be a positive integer, and a pixel of rounding is
    // cheaper than a label that ends one glyph short of fitting.
    return width.ceil().clamp(1, 1 << 20);
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.segment,
    required this.isSelected,
    required this.onTap,
  });

  final SegmentedControlItem<T> segment;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final motion = context.motion;
    final enabled = onTap != null;
    final Color foreground;
    if (!enabled) {
      foreground = colors.textDisabled;
    } else {
      foreground = isSelected ? colors.textPrimary : colors.textSecondary;
    }

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: motion.instant,
          curve: motion.instantCurve,
          constraints: const BoxConstraints(
            // Not `buttonHeightSmall`: a segment is the whole tap target —
            // there is no room around it inside the track, and the track's
            // own parents clip a hit test to their bounds, so a transparent
            // margin like `CheckButton`'s cannot reach past it. At 36 the
            // four diagnostics tabs and the three routing modes were the
            // last controls under this design system's own floor. 48 is also
            // what a text field and an icon button on the same screens are,
            // so the row now lines up with them instead of reading denser.
            minHeight: CommySizes.minTapTarget,
          ),
          padding: EdgeInsets.symmetric(horizontal: spacing.s2),
          decoration: BoxDecoration(
            color: isSelected ? colors.bgOverlay : CommyColors.transparent,
            borderRadius: context.radii.xsAll,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (segment.icon != null) ...<Widget>[
                Icon(
                  segment.icon,
                  size: CommySizes.iconInline,
                  color: foreground,
                ),
                SizedBox(width: spacing.s1),
              ],
              Flexible(
                child: Text(
                  segment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.typography.captionStrong.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
