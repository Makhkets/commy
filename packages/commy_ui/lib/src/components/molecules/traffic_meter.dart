import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/util/byte_format.dart';
import 'package:flutter/material.dart';

/// Up and down rates with tabular figures and automatic units.
///
/// When [isActive] is false the numbers are shown as zeros in
/// `text/disabled` rather than hidden: the row must not jump the moment the
/// tunnel comes up.
class TrafficMeter extends StatelessWidget {
  /// Creates a traffic meter.
  const TrafficMeter({
    required this.uplink,
    required this.downlink,
    this.isActive = true,
    this.isVertical = false,
    super.key,
  });

  /// Bytes per second going out.
  final int uplink;

  /// Bytes per second coming in.
  final int downlink;

  /// Whether the tunnel is carrying traffic.
  final bool isActive;

  /// Whether to stack the two readouts instead of putting them side by side.
  final bool isVertical;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final color = isActive ? colors.textPrimary : colors.textDisabled;

    final up = _Readout(
      icon: CommyIcons.arrowUp,
      value: CommyByteFormat.rate(isActive ? uplink : 0),
      color: color,
    );
    final down = _Readout(
      icon: CommyIcons.arrowDown,
      value: CommyByteFormat.rate(isActive ? downlink : 0),
      color: color,
    );

    if (isVertical) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[up, SizedBox(height: spacing.s1), down],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[up, SizedBox(width: spacing.s4), down],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: CommySizes.iconInline, color: color),
        SizedBox(width: context.spacing.s1),
        Text(
          value,
          maxLines: 1,
          style: context.typography.monoStrong.copyWith(color: color),
        ),
      ],
    );
  }
}
