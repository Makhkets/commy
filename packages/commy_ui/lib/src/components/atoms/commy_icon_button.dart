import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A square, icon-only button.
///
/// The tap target is [CommySizes.iconButtonSize] — 48 dp — which is the floor
/// from the pre-merge checklist, not a suggestion. The icon itself is 20.
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

  /// Icon colour. Defaults to `text/secondary`, or `text/primary` when
  /// [isSelected].
  final Color? color;

  /// Icon size. Defaults to [CommySizes.iconControl].
  final double? size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;
    final enabled = onPressed != null;
    final Color foreground;
    if (!enabled) {
      foreground = colors.textDisabled;
    } else {
      foreground =
          color ?? (isSelected ? colors.textPrimary : colors.textSecondary);
    }

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: Material(
        color: isSelected ? colors.accentWash : CommyColors.transparent,
        borderRadius: radii.smAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radii.smAll,
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
    );

    final label = tooltip;
    if (label == null) {
      return button;
    }
    return Tooltip(message: label, child: button);
  }
}
