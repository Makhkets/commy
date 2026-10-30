import 'package:commy_ui/src/components/commy_pressable.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A round, icon-only button.
///
/// The tap target is [CommySizes.iconButtonSize] — 48 dp — which is the floor
/// from the pre-merge checklist, not a suggestion. The icon itself is 20.
/// Ink by default: in a monochrome system the ink *is* the tint, and an
/// icon-only control has to look like one. A press greys a circle under the
/// finger and shrinks the button to 97 % (docs/04-design-system.md §8).
class CommyIconButton extends StatelessWidget {
  /// Creates an icon button.
  const CommyIconButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.isSelected = false,
    this.color,
    this.size,
    super.key,
  });

  /// Lucide icon to draw.
  final IconData icon;

  /// Tap handler. `null` disables the button.
  final VoidCallback? onPressed;

  /// Label announced to assistive technology. Required: an icon on its own
  /// says nothing to a screen reader.
  final String semanticLabel;

  /// Tooltip text, on platforms that show one. Already translated.
  final String? tooltip;

  /// Whether the button is in a latched, selected state.
  final bool isSelected;

  /// Icon colour. Defaults to `ink`.
  final Color? color;

  /// Icon size. Defaults to [CommySizes.iconControl].
  final double? size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shape = context.radii.pillAll;
    final enabled = onPressed != null;
    final Color foreground;
    if (!enabled) {
      foreground = colors.textDisabled;
    } else {
      foreground = color ?? colors.textPrimary;
    }

    final button = Semantics(
      button: true,
      enabled: enabled,
      // Said, not only painted. The latched state is a wash at 1.1:1 and a
      // change of icon colour, and the tablet rail is built from these: with
      // the flag left out, TalkBack read all four sections alike and never
      // which one was open — the desktop sidebar has always said it.
      selected: isSelected,
      label: semanticLabel,
      child: CommyPressable(
        enabled: enabled,
        child: Material(
          color: isSelected ? colors.fill : CommyColors.transparent,
          borderRadius: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            borderRadius: shape,
            child: SizedBox(
              width: CommySizes.iconButtonSize,
              height: CommySizes.iconButtonSize,
              child: Icon(
                icon,
                size: size ?? CommySizes.iconControl,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );

    final label = tooltip;
    if (label == null) {
      return button;
    }
    return Tooltip(message: label, child: button);
  }
}
