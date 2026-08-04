import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A checkbox, 20 dp on a 48 dp tap target.
class CommyCheckbox extends StatelessWidget {
  /// Creates a checkbox.
  const CommyCheckbox({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  /// Current state.
  final bool value;

  /// Called with the new state. `null` disables the checkbox.
  final ValueChanged<bool>? onChanged;

  /// Label announced to assistive technology.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final enabled = onChanged != null;

    final Color fill;
    final Color border;
    if (!enabled) {
      fill = value ? colors.bgOverlay : CommyColors.transparent;
      border = colors.borderSubtle;
    } else if (value) {
      fill = colors.accentSolid;
      border = colors.accentSolid;
    } else {
      fill = CommyColors.transparent;
      border = colors.borderStrong;
    }

    return Semantics(
      checked: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          width: CommySizes.minTapTarget,
          height: CommySizes.minTapTarget,
          child: Center(
            child: AnimatedContainer(
              duration: motion.fast,
              curve: motion.fastCurve,
              width: CommySizes.checkboxSize,
              height: CommySizes.checkboxSize,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: context.radii.xsAll,
                border: Border.all(color: border),
              ),
              child: value
                  ? Icon(
                      CommyIcons.check,
                      size: CommySizes.iconInline,
                      color: enabled
                          ? colors.accentOnSolid
                          : colors.textDisabled,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
