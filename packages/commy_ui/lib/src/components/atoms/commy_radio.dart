import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A radio button, 20 dp on a 48 dp tap target.
///
/// Generic over the value it selects, so that a group can be built from a
/// domain enum without stringly-typed glue.
class CommyRadio<T> extends StatelessWidget {
  /// Creates a radio button.
  const CommyRadio({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  /// The value this button stands for.
  final T value;

  /// The value currently selected in the group.
  final T? groupValue;

  /// Called with [value] when the button is tapped. `null` disables it.
  final ValueChanged<T>? onChanged;

  /// Label announced to assistive technology.
  final String? semanticLabel;

  /// Whether this button is the selected one.
  bool get isSelected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final enabled = onChanged != null;

    final Color border;
    if (!enabled) {
      border = colors.borderSubtle;
    } else if (isSelected) {
      border = colors.accentSolid;
    } else {
      border = colors.borderStrong;
    }

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: isSelected,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(value) : null,
        child: SizedBox(
          width: CommySizes.minTapTarget,
          height: CommySizes.minTapTarget,
          child: Center(
            child: Container(
              width: CommySizes.radioSize,
              height: CommySizes.radioSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: border),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: motion.fast,
                  curve: motion.fastCurve,
                  width: isSelected ? CommySizes.radioDot : 0,
                  height: isSelected ? CommySizes.radioDot : 0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: enabled
                        ? colors.accentSolid
                        : CommyColors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
