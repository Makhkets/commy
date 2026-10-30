import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/util/byte_format.dart';
import 'package:commy_ui/src/util/duration_format.dart';
import 'package:flutter/material.dart';

/// Session length, download and upload — the line under the answer at the
/// top of the main screen, while the tunnel is up.
///
/// Quiet on purpose: `numericBody` — Inter with tabular figures, so a digit
/// that changes once a second moves nothing around it — in `ink-2`, starting
/// at the leading edge under the answer it belongs to. Digits that tick at
/// 44 dp turn a calm screen into an instrument panel; here they are a line of
/// fact under "Connected".
///
/// While nothing is connected the row shows zeros in `ink-disabled` rather
/// than hiding, for a caller that keeps it on screen.
///
/// At large text scales the readouts reflow instead of overflowing, and the
/// down and up rates stay together as a pair: a plain wrap once split them
/// across the clock. The clock keeps the first line.
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
        isActive ? context.colors.textSecondary : context.colors.textDisabled;

    final up = _Metric(
      icon: CommyIcons.arrowUp,
      value: CommyByteFormat.rate(
        isActive ? uplink : 0,
        locale: Localizations.maybeLocaleOf(context),
      ),
      color: color,
      label: uplinkLabel,
    );
    final clock = _Metric(
      icon: CommyIcons.clock,
      value: CommyDurationFormat.clock(isActive ? session : Duration.zero),
      color: color,
      label: sessionLabel,
    );
    final down = _Metric(
      icon: CommyIcons.arrowDown,
      value: CommyByteFormat.rate(
        isActive ? downlink : 0,
        locale: Localizations.maybeLocaleOf(context),
      ),
      color: color,
      label: downlinkLabel,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final upWidth = _widthOf(context, up.value);
        final clockWidth = _widthOf(context, clock.value);
        final downWidth = _widthOf(context, down.value);
        final gap = spacing.s4;

        // Everything on one line, from the leading edge.
        if (upWidth + clockWidth + downWidth + gap * 2 <= available) {
          return Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: spacing.s1,
            children: <Widget>[clock, down, up],
          );
        }
        // The clock keeps the first line, the pair takes the second.
        if (upWidth + downWidth + gap <= available) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              clock,
              SizedBox(height: spacing.s1),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: gap,
                children: <Widget>[down, up],
              ),
            ],
          );
        }
        // Not even two fit: one per line, in reading order.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            clock,
            SizedBox(height: spacing.s1),
            down,
            SizedBox(height: spacing.s1),
            up,
          ],
        );
      },
    );
  }

  /// Width one readout needs: the glyph, the gap and the figure, measured
  /// with the style and the text scale it will actually be drawn with.
  double _widthOf(BuildContext context, String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: context.typography.numericBody),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width + CommySizes.iconInline + context.spacing.s1;
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
          style: context.typography.numericBody.copyWith(color: color),
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
