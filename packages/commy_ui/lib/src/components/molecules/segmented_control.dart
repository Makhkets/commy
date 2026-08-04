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
            minHeight: CommySizes.buttonHeightSmall,
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
