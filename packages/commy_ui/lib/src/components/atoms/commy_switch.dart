import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A two-state switch, 44 × 26 with a 20 dp thumb.
///
/// Hand-built rather than themed from Material: the Material switch insists on
/// its own thumb elevation and ripple radius, both of which fight the flat
/// graphite surface.
class CommySwitch extends StatelessWidget {
  /// Creates a switch.
  const CommySwitch({
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  /// Current state.
  final bool value;

  /// Called with the new state. `null` disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Label announced to assistive technology.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final enabled = onChanged != null;

    final Color track;
    final Color thumb;
    if (!enabled) {
      track = colors.bgOverlay;
      thumb = colors.textDisabled;
    } else if (value) {
      track = colors.accentSolid;
      thumb = colors.accentOnSolid;
    } else {
      track = colors.bgOverlay;
      thumb = colors.textTertiary;
    }

    return Semantics(
      toggled: value,
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
              width: CommySizes.switchWidth,
              height: CommySizes.switchHeight,
              padding: const EdgeInsets.all(CommySizes.switchPadding),
              decoration: BoxDecoration(
                color: track,
                borderRadius: context.radii.fullAll,
                border: value
                    ? null
                    : Border.all(color: colors.borderDefault),
              ),
              child: AnimatedAlign(
                duration: motion.fast,
                curve: motion.fastCurve,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: CommySizes.switchThumb,
                  height: CommySizes.switchThumb,
                  decoration: BoxDecoration(
                    color: thumb,
                    shape: BoxShape.circle,
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
