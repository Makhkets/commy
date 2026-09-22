import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A pill-shaped, tappable filter or token.
///
/// A chip is a badge that does something: it selects, it filters, it can be
/// removed. When neither [onTap] nor [onRemove] is given, reach for
/// `CommyBadge` instead.
class CommyChip extends StatelessWidget {
  /// Creates a chip.
  const CommyChip({
    required this.label,
    this.icon,
    this.isSelected = false,
    this.onTap,
    this.onRemove,
    this.removeSemanticLabel,
    super.key,
  });

  /// Text of the chip. Already translated; upper-cased on the way out.
  final String label;

  /// Optional leading Lucide icon.
  final IconData? icon;

  /// Whether the chip is currently on.
  final bool isSelected;

  /// Tap handler.
  final VoidCallback? onTap;

  /// When given, a trailing cross appears and calls this.
  final VoidCallback? onRemove;

  /// Label announced for the trailing cross. Required in practice whenever
  /// [onRemove] is given.
  final String? removeSemanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final foreground = isSelected ? colors.textPrimary : colors.textSecondary;
    final background = isSelected ? colors.accentWash : colors.bgOverlay;
    final border = isSelected ? colors.borderStrong : colors.borderDefault;

    // The visible pill stays the dense 36; the difference up to the minimum
    // tap target is transparent margin that still takes taps. Same idiom, and
    // the same arithmetic, as `CheckButton` — a chip is a control a person
    // pokes repeatedly (the log level filters are four of them in a row), and
    // a 36pt box is under the 48 this design system sets as its own floor.
    const tapMargin =
        (CommySizes.minTapTarget - CommySizes.buttonHeightSmall) / 2;

    return Semantics(
      button: onTap != null,
      selected: isSelected,
      child: Material(
        color: CommyColors.transparent,
        borderRadius: context.radii.fullAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: context.radii.fullAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: tapMargin),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: CommySizes.buttonHeightSmall,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.s3,
                vertical: spacing.s1,
              ),
              decoration: BoxDecoration(
                color: background,
                borderRadius: context.radii.fullAll,
                border: Border.all(color: border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(
                      icon,
                      size: CommySizes.iconInline,
                      color: foreground,
                    ),
                    SizedBox(width: spacing.s1),
                  ],
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          context.typography.label.copyWith(color: foreground),
                    ),
                  ),
                  if (onRemove != null) ...<Widget>[
                    SizedBox(width: spacing.s1),
                    Semantics(
                      button: true,
                      label: removeSemanticLabel,
                      child: GestureDetector(
                        onTap: onRemove,
                        child: Icon(
                          CommyIcons.close,
                          size: CommySizes.iconInline,
                          color: foreground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
