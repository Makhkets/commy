import 'dart:async';
import 'dart:math' as math;

import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// An indeterminate spinner drawn as a quarter-turn arc.
///
/// Painted rather than taken from Material because the framework's
/// [CircularProgressIndicator] keeps animating even when the platform asks
/// for reduced motion. Here the rotation simply stops and a static arc is
/// left on screen.
class CommySpinner extends StatefulWidget {
  /// Creates a spinner.
  const CommySpinner({
    this.size,
    this.color,
    this.semanticLabel,
    super.key,
  });

  /// Diameter. Defaults to [CommySizes.spinnerSize].
  final double? size;

  /// Arc colour. Defaults to `text/secondary`.
  final Color? color;

  /// Label announced to assistive technology, when the spinner is the only
  /// thing on screen saying that work is in progress.
  final String? semanticLabel;

  @override
  State<CommySpinner> createState() => _CommySpinnerState();
}

class _CommySpinnerState extends State<CommySpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CommyMotion.standard.spinner,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final diameter = widget.size ?? CommySizes.spinnerSize;
    final color = widget.color ?? context.colors.textSecondary;
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SpinnerPainter(
              progress: _controller.value,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  const _SpinnerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = CommySizes.spinnerStroke;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final start = -math.pi / 2 + progress * 2 * math.pi;
    canvas.drawArc(
      rect,
      start,
      CommySizes.spinnerSweep * 2 * math.pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_SpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
