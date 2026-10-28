import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/components/molecules/segmented_control_item.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A row of mutually exclusive options on one track, the iOS way
/// (docs/04-design-system.md §8).
///
/// Used for the routing mode — global, rules, direct — where the three
/// choices have to be visible at once because the difference between them is
/// the whole point of the screen, and for the diagnostics tabs.
///
/// The track is the neutral `fill`; the chosen option sits on a thumb that
/// *travels* to the next one on the `snappy` spring, retargeting from wherever
/// it is, so a quick second tap never makes it jump. The thumb is white on
/// light and `#636366` on dark, with the small shadow of a floating part —
/// and an edge of `line-strong`: the fill alone is 1.2:1 against the track,
/// and what says which mode is on has to reach 3:1.
///
/// Segments share the track in proportion to how wide their labels actually
/// are, not in equal slices. Equal slices look tidy with labels of one
/// length and fail with real ones: four Russian diagnostics tabs on a 390pt
/// phone gave every segment the same 87pt, which is room to spare for
/// "Логи" and not enough for "Соединения" — so the two words a person
/// needs to tell apart both arrived as an ellipsis. Proportional shares fit
/// all four, and when the labels genuinely cannot fit they shorten by the
/// same ratio instead of the same number of pixels.
///
/// The visible track is 36 dp; the control is 48 tall, and the margin above
/// and below still takes taps, so every segment is a full-size target.
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
    final motion = context.motion;
    final radii = context.radii;
    final enabled = onChanged != null;
    final weights = <int>[
      for (final segment in segments) _widthOf(context, segment),
    ];
    final total = weights.fold<int>(0, (sum, weight) => sum + weight);
    final selected = segments.indexWhere((segment) => segment.value == value);
    const inset = CommySizes.segmentedInset;
    const margin = (CommySizes.minTapTarget - CommySizes.segmentedHeight) / 2;
    final thumbRadius = BorderRadius.circular(radii.control - inset);

    return Opacity(
      opacity: enabled ? 1 : CommySizes.disabledOpacity,
      child: SizedBox(
        height: CommySizes.minTapTarget,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth - inset * 2;
            double startOf(int index) {
              final before = weights
                  .take(index)
                  .fold<int>(0, (sum, weight) => sum + weight);
              return inset + width * before / total;
            }

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  top: margin,
                  bottom: margin,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.fill,
                      borderRadius: radii.controlAll,
                    ),
                  ),
                ),
                if (selected >= 0)
                  AnimatedPositioned(
                    duration: motion.fast,
                    curve: motion.fastCurve,
                    left: startOf(selected),
                    width: width * weights[selected] / total,
                    top: margin + inset,
                    bottom: margin + inset,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.segmentThumb,
                        borderRadius: thumbRadius,
                        border: Border.all(color: colors.borderStrong),
                        boxShadow: context.elevation.thumb,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: inset),
                  child: Row(
                    children: <Widget>[
                      for (var index = 0; index < segments.length; index++)
                        Expanded(
                          flex: weights[index],
                          child: _Segment<T>(
                            segment: segments[index],
                            isSelected: index == selected,
                            radius: thumbRadius,
                            onTap: enabled
                                ? () => onChanged!(segments[index].value)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
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
    required this.radius,
    required this.onTap,
  });

  final SegmentedControlItem<T> segment;
  final bool isSelected;
  final BorderRadius radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final foreground = isSelected ? colors.textPrimary : colors.textSecondary;
    const margin = (CommySizes.minTapTarget - CommySizes.segmentedHeight) / 2;

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: onTap != null,
      child: CommyFocusable(
        onActivate: onTap,
        builder: (context, {required isFocused}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: margin + CommySizes.segmentedInset,
            ),
            child: Container(
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: spacing.s2),
              // The focus ring, on the segment's own shape: segments touch,
              // and the track's parents clip anything drawn past its edge.
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: CommyFocusable.ring(colors, isFocused: isFocused),
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
        ),
      ),
    );
  }
}
