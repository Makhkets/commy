import 'package:commy_ui/src/components/commy_focusable.dart';
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
      child: CommyFocusable(
        onActivate: enabled ? () => onChanged!(!value) : null,
        builder: (context, {required isFocused}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: SizedBox(
            width: CommySizes.minTapTarget,
            height: CommySizes.minTapTarget,
            child: Center(
              // The focus ring hugs the track from outside, with no gap:
              // 44 of track and two rings of 2 are exactly the 48 there is.
              // Outside, so it reads on the chalk fill as on the empty one.
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: context.radii.fullAll,
                  border: CommyFocusable.ring(colors, isFocused: isFocused),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(CommySizes.borderThick),
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
          ),
        ),
      ),
    );
  }
}
