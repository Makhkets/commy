import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A dot plus a word. Never a colour on its own.
///
/// This is the component the contrast rule of the design document is really
/// about: connection state is colour **and** shape **and** text. Remove the
/// text and the pill stops being usable for eight percent of men.
class StatusPill extends StatelessWidget {
  /// Creates a status pill.
  const StatusPill({
    required this.label,
    required this.tone,
    this.icon,
    super.key,
  });

  /// Text of the pill. Already translated. Never optional.
  final String label;

  /// Meaning the pill carries.
  final CommyTone tone;

  /// Optional Lucide icon shown instead of the dot.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final foreground = tone.foreground(colors);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.wash(colors),
        borderRadius: context.radii.fullAll,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s3,
          vertical: spacing.s1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon == null)
              Container(
                width: CommySizes.statusDot,
                height: CommySizes.statusDot,
                decoration: BoxDecoration(
                  color: foreground,
                  shape: BoxShape.circle,
                ),
              )
            else
              Icon(icon, size: CommySizes.iconInline, color: foreground),
            SizedBox(width: spacing.s2),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typography.captionStrong.copyWith(
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
