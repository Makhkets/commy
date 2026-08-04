import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A small, static label. Not tappable — that is what a chip is for.
///
/// Uses the `Label` style, which is always upper case; the transform is
/// applied here so callers pass ordinary text.
class CommyBadge extends StatelessWidget {
  /// Creates a badge.
  const CommyBadge({
    required this.label,
    this.tone = CommyTone.neutral,
    this.icon,
    super.key,
  });

  /// Text of the badge. Already translated; upper-cased on the way out.
  final String label;

  /// Meaning the badge carries.
  final CommyTone tone;

  /// Optional leading Lucide icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final foreground = tone.foreground(colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.wash(colors),
        borderRadius: context.radii.xsAll,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s2,
          vertical: spacing.s1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: CommySizes.iconInline, color: foreground),
              SizedBox(width: spacing.s1),
            ],
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.typography.label.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
