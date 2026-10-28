import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A small, static label. Not tappable — that is what a chip is for.
///
/// `label` style — 12 / 16, Semi Bold — in the case the caller wrote it:
/// sentence case for words ("Прямо"), capitals only for names that are
/// spelled that way. A tracked-out capital badge is one of the marks of a
/// templated interface (docs/04-design-system.md §13).
class CommyBadge extends StatelessWidget {
  /// Creates a badge.
  const CommyBadge({
    required this.label,
    this.tone = CommyTone.neutral,
    this.icon,
    super.key,
  });

  /// Text of the badge. Already translated, drawn as given.
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
          vertical: spacing.s05,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: CommySizes.iconInline, color: foreground),
              SizedBox(width: spacing.s1),
            ],
            Text(
              label,
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
