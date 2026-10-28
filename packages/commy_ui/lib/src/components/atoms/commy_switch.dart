import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A two-state switch with the geometry of the iOS one: a 51 × 31 track and a
/// 27 dp thumb that stretches to 33 while a finger holds it.
///
/// Monochrome on purpose (docs/04-design-system.md §8): a switch that is on
/// fills with the action — ink on light, chalk on dark — and never with green,
/// which in this product means one thing only, a working connection. The thumb
/// is white with a small shadow on light; on dark it turns black on the chalk
/// track, where a white one would vanish.
///
/// The thumb travels on the `snappy` spring and retargets from wherever it is,
/// so flipping a switch twice in a row never jumps. A disabled switch fades as
/// a whole, as iOS shows it.
class CommySwitch extends StatefulWidget {
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
  State<CommySwitch> createState() => _CommySwitchState();
}

class _CommySwitchState extends State<CommySwitch> {
  bool _pressed = false;

  bool get _enabled => widget.onChanged != null;

  void _toggle() => widget.onChanged?.call(!widget.value);

  void _press(bool value) {
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final value = widget.value;
    final track = value ? colors.accentSolid : colors.fill;
    final thumb = value ? colors.accentOnSolid : colors.thumb;
    final thumbWidth = _pressed && _enabled && !context.reduceMotion
        ? CommySizes.switchThumbPressed
        : CommySizes.switchThumb;

    Widget control({required bool isFocused}) => SizedBox(
          width: CommySizes.minTapTarget +
              CommySizes.switchWidth -
              CommySizes.switchHeight,
          height: CommySizes.minTapTarget,
          child: Center(
            // The focus ring hugs the track from outside, so it reads on the
            // filled track as on the empty one.
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: context.radii.pillAll,
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
                    borderRadius: context.radii.pillAll,
                  ),
                  child: AnimatedAlign(
                    duration: motion.fast,
                    curve: motion.fastCurve,
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: motion.fast,
                      curve: motion.fastCurve,
                      width: thumbWidth,
                      height: CommySizes.switchThumb,
                      decoration: BoxDecoration(
                        color: thumb,
                        borderRadius: context.radii.pillAll,
                        boxShadow: context.elevation.thumb,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

    return Semantics(
      toggled: value,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: CommyFocusable(
        onActivate: _enabled ? _toggle : null,
        builder: (context, {required isFocused}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _toggle : null,
          onTapDown: _enabled ? (_) => _press(true) : null,
          onTapUp: _enabled ? (_) => _press(false) : null,
          onTapCancel: _enabled ? () => _press(false) : null,
          child: Opacity(
            opacity: _enabled ? 1 : CommySizes.disabledOpacity,
            child: control(isFocused: isFocused),
          ),
        ),
      ),
    );
  }
}
