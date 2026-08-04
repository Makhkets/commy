import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// A damped-spring curve, expressed the way Figma expresses one: a damping
/// ratio plus a response time.
///
/// Only `motion/connect` uses it, and only for the connection state change —
/// the one moment in the product where a bit of physical overshoot reads as
/// "something happened" rather than as decoration.
///
/// Time is normalised: [response] is a fraction of the animation's own
/// duration, not seconds. With the default 0.5 the spring completes roughly
/// two periods' worth of settling inside the 620 ms of `motion/connect`.
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
    final oscillation = math.cos(damped * t) +
        (zeta * omega / damped) * math.sin(damped * t);
    return 1 - decay * oscillation;
  }

  @override
  String toString() =>
      'CommySpringCurve($dampingRatio / $response)';
}
