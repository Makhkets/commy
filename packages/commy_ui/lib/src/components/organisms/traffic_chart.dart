import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/thresholds.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Throughput over the last minute, as a sparkline.
///
/// One series, not two: the chart says "traffic is moving, and roughly this
/// much", which is all a diagnostics screen needs from a 48 dp strip. It is
/// drawn in `accent/solid` rather than in a status colour — in this product
/// colour means connection state and nothing else, and a chart line is not a
/// connection state.
///
/// Only the vertical scale animates, and only because a chart that rescales
/// in one frame when a new peak arrives looks like it jumped to different
/// data. Under `MediaQuery.disableAnimations` every motion token collapses to
/// zero, so the rescale becomes the instant state change accessibility asks
/// for — the same single code path, no fork.
class TrafficChart extends StatelessWidget {
  /// Creates a sparkline.
  const TrafficChart({
    required this.samples,
    required this.semanticLabel,
    this.window = CommyThresholds.chartWindow,
    this.height = CommySizes.chartHeight,
    super.key,
  });

  /// Samples in chronological order, oldest first. Anything older than
  /// [window] before the newest sample is ignored.
  final List<TrafficSample> samples;

  /// One sentence describing the chart for a screen reader, for example
  /// "трафик за 60 секунд, пик 1,2 МБ/с". Required: a painted line with no
  /// text alternative is invisible to assistive technology, and this is the
  /// only place the numbers exist.
  final String semanticLabel;

  /// How far back the chart looks.
  final Duration window;

  /// Height of the strip.
  final double height;

  /// The samples as points: `dx` is the position inside [window] in `0..1`,
  /// `dy` is the combined rate in bytes per second.
  ///
  /// Normalised here rather than in the painter so that the painter has no
  /// opinion about time.
  List<Offset> get plottedPoints {
    final span = window.inMicroseconds;
    if (samples.isEmpty || span <= 0) {
      return const <Offset>[];
    }
    final start = samples.last.at.subtract(window);
    final points = <Offset>[];
    for (final sample in samples) {
      if (sample.at.isBefore(start)) {
        continue;
      }
      final position = sample.at.difference(start).inMicroseconds / span;
      points.add(
        Offset(position.clamp(0, 1).toDouble(), sample.rate.toDouble()),
      );
    }
    return points;
  }

  /// Tallest sample in the window, and never zero: a line that never moved
  /// still needs a scale to be drawn against.
  static double _peakOf(List<Offset> points) {
    double peak = 0;
    for (final point in points) {
      if (point.dy > peak) {
        peak = point.dy;
      }
    }
    if (peak <= 0) {
      return 1;
    }
    return peak;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final points = plottedPoints;
    final peak = _peakOf(points);

    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: peak),
          duration: motion.base,
          curve: motion.baseCurve,
          builder: (context, scale, _) => CustomPaint(
            painter: _SparklinePainter(
              points: points,
              peak: scale <= 0 ? peak : scale,
              line: colors.accentSolid,
              fill: colors.accentWash,
              baseline: colors.borderSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({
    required this.points,
    required this.peak,
    required this.line,
    required this.fill,
    required this.baseline,
  });

  final List<Offset> points;
  final double peak;
  final Color line;
  final Color fill;
  final Color baseline;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = CommySizes.chartStroke / 2;
    final base = size.height - inset;
    final span = base - inset;

    canvas.drawLine(
      Offset(0, base),
      Offset(size.width, base),
      Paint()
        ..color = baseline
        ..strokeWidth = CommySizes.borderThin,
    );

    if (points.isEmpty) {
      return;
    }

    final plotted = <Offset>[
      for (final point in points)
        Offset(
          point.dx * size.width,
          base - (point.dy / peak).clamp(0, 1).toDouble() * span,
        ),
    ];

    if (plotted.length > 1) {
      final stroke = Path()..moveTo(plotted.first.dx, plotted.first.dy);
      for (final offset in plotted.skip(1)) {
        stroke.lineTo(offset.dx, offset.dy);
      }
      final area = Path.from(stroke)
        ..lineTo(plotted.last.dx, base)
        ..lineTo(plotted.first.dx, base)
        ..close();
      canvas
        ..drawPath(area, Paint()..color = fill)
        ..drawPath(
          stroke,
          Paint()
            ..color = line
            ..style = PaintingStyle.stroke
            ..strokeWidth = CommySizes.chartStroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
    }

    canvas.drawCircle(
      plotted.last,
      CommySizes.chartStroke * 2,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      oldDelegate.peak != peak ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill ||
      oldDelegate.baseline != baseline ||
      !listEquals(oldDelegate.points, points);
}
