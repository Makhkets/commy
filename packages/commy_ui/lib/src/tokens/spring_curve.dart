import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A damped-spring curve, expressed the way a designer names a spring: a
/// damping ratio plus a response time.
///
/// What the implicit animations run on (`CommySprings.curve`): laid over
/// 1.5 × T it moves exactly like the interactive `SpringSimulation` of the
/// same preset, and the implicit widgets retarget it from the value on
/// screen (docs/04-design-system.md §7.2).
///
/// Time is normalised: [response] is a fraction of the animation's own
/// duration, not seconds.
class CommySpringCurve extends Curve {
  /// Creates a spring with the given [dampingRatio] and [response].
  const CommySpringCurve({
    this.dampingRatio = 0.85,
    this.response = 0.5,
  })  : assert(dampingRatio > 0, 'damping ratio must be positive'),
        assert(response > 0, 'response must be positive');

  /// How quickly the oscillation dies out. Below 1 the curve overshoots.
  final double dampingRatio;

  /// Natural period, as a fraction of the total duration.
  final double response;

  @override
  double transformInternal(double t) {
    final omega = 2 * math.pi / response;
    final zeta = dampingRatio;
    if (zeta >= 1) {
      // Critically damped: no overshoot, exponential approach.
      return 1 - math.exp(-omega * t) * (1 + omega * t);
    }
    final damped = omega * math.sqrt(1 - zeta * zeta);
    final decay = math.exp(-zeta * omega * t);
    final oscillation =
        math.cos(damped * t) + (zeta * omega / damped) * math.sin(damped * t);
    return 1 - decay * oscillation;
  }

  @override
  String toString() => 'CommySpringCurve($dampingRatio / $response)';
}
