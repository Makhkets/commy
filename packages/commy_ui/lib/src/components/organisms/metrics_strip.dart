import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/util/byte_format.dart';
import 'package:commy_ui/src/util/duration_format.dart';
import 'package:flutter/material.dart';

/// Upload, session length and download — one line above the connect button.
///
/// The big timer that used to sit inside the ring is gone on purpose: those
/// digits change once a second, and at 44 dp they turn a calm screen into an
/// instrument panel. Here they are `Mono/Strong` with tabular figures, where
/// a changing digit does not move anything around it.
///
/// While nothing is connected the row shows zeros in `text/disabled` rather
/// than hiding: it must not jump the moment the tunnel comes up.
///
/// At large text scales the three readouts reflow onto a second line instead
/// of overflowing — they are laid out as a [Wrap], not a [Row].
class MetricsStrip extends StatelessWidget {
  /// Creates a metrics strip.
  ///
  /// The three `*Label` strings are finished, translated words announced to
  /// assistive technology — this package owns no text. Without them a screen
  /// reader would read three bare numbers, because the direction is carried
  /// by an arrow that has no words of its own.
  const MetricsStrip({
    required this.uplink,
    required this.downlink,
    required this.session,
    this.isActive = false,
    this.uplinkLabel,
    this.sessionLabel,
    this.downlinkLabel,
    super.key,
  });

  /// Bytes per second going out.
  final int uplink;

  /// Bytes per second coming in.
  final int downlink;

  /// How long the current session has been up.
  final Duration session;

  /// Whether the tunnel is up. When false every figure reads zero.
  final bool isActive;

  /// Word for the upload figure, for assistive technology.
  final String? uplinkLabel;

  /// Word for the session length, for assistive technology.
  final String? sessionLabel;

  /// Word for the download figure, for assistive technology.
  final String? downlinkLabel;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final color =
        isActive ? context.colors.textPrimary : context.colors.textDisabled;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: spacing.s4,
      runSpacing: spacing.s1,
      children: <Widget>[
        _Metric(
          icon: CommyIcons.arrowUp,
          value: CommyByteFormat.rate(isActive ? uplink : 0),
          color: color,
          label: uplinkLabel,
        ),
        _Metric(
          icon: CommyIcons.clock,
          value: CommyDurationFormat.clock(isActive ? session : Duration.zero),
          color: color,
          label: sessionLabel,
        ),
        _Metric(
          icon: CommyIcons.arrowDown,
          value: CommyByteFormat.rate(isActive ? downlink : 0),
          color: color,
          label: downlinkLabel,
        ),
      ],
    );
  }
}

/// One icon and one figure.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.value,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final String value;
  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final row = Row(
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
    if (label == null) {
      return row;
    }
    return Semantics(
      label: label,
      value: value,
      excludeSemantics: true,
      child: row,
    );
  }
}
