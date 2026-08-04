import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/thresholds.dart';
import 'package:commy_ui/src/util/duration_format.dart';
import 'package:flutter/material.dart';

/// Bars plus a number plus a colour.
///
/// Three signals for one fact, on purpose: the bars survive a colour-blind
/// reader, the number survives a small screen, and the colour is what the eye
/// catches while scrolling. Below 100 ms is fast, below 300 ms is medium,
/// anything else is slow, and an unmeasured node shows an em dash rather than
/// a zero — zero would read as "instant".
class LatencyBadge extends StatelessWidget {
  /// Creates a latency badge.
  const LatencyBadge({
    required this.latency,
    this.showNumber = true,
    super.key,
  });

  /// Measured round trip, or `null` when the node has never been probed.
  final Duration? latency;

  /// Whether the millisecond figure is shown next to the bars.
  final bool showNumber;

  /// How many of the three bars are lit: 3 fast, 2 medium, 1 slow, 0 unknown.
  int get filledBars {
    final value = latency;
    if (value == null) {
      return 0;
    }
    if (value < CommyThresholds.latencyFast) {
      return CommySizes.latencyBarCount;
    }
    if (value < CommyThresholds.latencySlow) {
      return CommySizes.latencyBarCount - 1;
    }
    return 1;
  }

  /// Meaning this measurement carries.
  CommyTone get tone {
    final value = latency;
    if (value == null) {
      return CommyTone.idle;
    }
    if (value < CommyThresholds.latencyFast) {
      return CommyTone.connected;
    }
    if (value < CommyThresholds.latencySlow) {
      return CommyTone.connecting;
    }
    return CommyTone.error;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final value = latency;
    final foreground =
        value == null ? colors.textDisabled : tone.foreground(colors);
    final text = value == null
        ? CommyDurationFormat.unknown
        : CommyDurationFormat.milliseconds(value);

    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (var index = 0; index < CommySizes.latencyBarCount; index++)
            Padding(
              padding: EdgeInsets.only(
                right: index == CommySizes.latencyBarCount - 1
                    ? 0
                    : CommySizes.latencyBarGap,
              ),
              child: _Bar(
                index: index,
                isLit: index < filledBars,
                color: foreground,
                dimColor: colors.borderDefault,
              ),
            ),
          if (showNumber) ...<Widget>[
            SizedBox(width: spacing.s2),
            Text(
              text,
              style: context.typography.monoSmall.copyWith(
                color: foreground,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.index,
    required this.isLit,
    required this.color,
    required this.dimColor,
  });

  final int index;
  final bool isLit;
  final Color color;
  final Color dimColor;

  @override
  Widget build(BuildContext context) {
    const steps = CommySizes.latencyBarCount;
    final height = CommySizes.latencyBarHeight * (index + 1) / steps;
    return Container(
      width: CommySizes.latencyBarWidth,
      height: height,
      decoration: BoxDecoration(
        color: isLit ? color : dimColor,
        borderRadius: BorderRadius.circular(CommySizes.latencyBarWidth),
      ),
    );
  }
}
