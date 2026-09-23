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
/// of overflowing. Which of them moves is decided here rather than left to a
/// [Wrap]: the up and down rates are read as a pair, and a plain wrap broke
/// exactly that pair — at 1.6x it produced "↑ 384 KB/s ⏱ 00:42:00" on one
/// line and a lone "↓ 3.0 MB/s" under it, so the two halves of one answer
/// were separated by the clock. The clock is the one that moves now.
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

        // Everything on one line: the original `Wrap`, unchanged, because
        // it is the only one of the two that shrinks to its content when the
        // parent hands it loose constraints — a `Row` would have spread the
        // three readouts to the edges of whatever it was given, which is a
        // different picture in every golden that measures this component.
        if (upWidth + clockWidth + downWidth + gap * 2 <= available) {
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: spacing.s1,
            children: <Widget>[up, clock, down],
          );
        }
        // The pair holds the line and the clock drops below it.
        if (upWidth + downWidth + gap <= available) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: gap,
                children: <Widget>[up, down],
              ),
              SizedBox(height: spacing.s1),
              Align(child: clock),
            ],
          );
        }
        // Not even two fit: one per line, in reading order.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            up,
            SizedBox(height: spacing.s1),
            down,
            SizedBox(height: spacing.s1),
            clock,
          ],
        );
      },
    );
  }

  /// Width one readout needs: the glyph, the gap and the figure, measured
  /// with the style and the text scale it will actually be drawn with.
  double _widthOf(BuildContext context, String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: context.typography.monoStrong),
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
