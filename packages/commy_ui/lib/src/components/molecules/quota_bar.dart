import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/thresholds.dart';
import 'package:flutter/material.dart';

/// Used against total, as a track that reddens towards the end.
///
/// Thresholds come from tokens, and the critical one is the same number the
/// domain uses for `SubscriptionUserInfo.isNearQuota` — a bar that turns red
/// at a different point from the warning text would be worse than no bar.
class QuotaBar extends StatelessWidget {
  /// Creates a quota bar.
  const QuotaBar({
    required this.ratio,
    this.leadingLabel,
    this.trailingLabel,
    this.semanticLabel,
    super.key,
  });

  /// Share of the quota already spent, clamped to `0..1`.
  final double ratio;

  /// Text above the track on the leading side. Already translated.
  final String? leadingLabel;

  /// Text above the track on the trailing side. Already translated.
  final String? trailingLabel;

  /// Announced to assistive technology in place of the two labels.
  final String? semanticLabel;

  /// [ratio] brought into range.
  double get clampedRatio => ratio.clamp(0, 1).toDouble();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final motion = context.motion;

    final Color fill;
    if (clampedRatio >= CommyThresholds.quotaCritical) {
      fill = colors.statusError;
    } else if (clampedRatio >= CommyThresholds.quotaWarn) {
      fill = colors.statusConnecting;
    } else {
      fill = colors.accentSolid;
    }

    final hasLabels = leadingLabel != null || trailingLabel != null;

    return Semantics(
      label: semanticLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (hasLabels) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    leadingLabel ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        type.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                if (trailingLabel != null)
                  Text(
                    trailingLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.monoSmall.copyWith(color: fill),
                  ),
              ],
            ),
            SizedBox(height: spacing.s1),
          ],
          ClipRRect(
            borderRadius: context.radii.fullAll,
            child: SizedBox(
              height: CommySizes.quotaBarHeight,
              child: ColoredBox(
                color: colors.bgInset,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FractionallySizedBox(
                    widthFactor: clampedRatio,
                    child: AnimatedContainer(
                      duration: motion.base,
                      curve: motion.baseCurve,
                      color: fill,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
