import 'package:commy_ui/src/tokens/spring_curve.dart';
import 'package:flutter/physics.dart';

/// The springs of docs/04-design-system.md §7.2, in the two shapes Flutter
/// takes them.
///
/// A spring is named the way a designer names one: ζ, the damping ratio (1
/// settles without overshoot, below 1 bounces), and T, its visual duration in
/// seconds. The physics follow from those two with a mass of 1:
///
/// ```text
/// stiffness = (2π / T)²        damping = 4π·ζ / T
/// ```
///
/// * As a [SpringDescription] for anything a finger can catch — a press, a
///   thumb, a sheet: `AnimationController.animateWith(SpringSimulation(…))`
///   starts from the value on screen and the velocity it already has, so the
///   motion can be interrupted and reversed at any instant.
/// * As a [CommySpringCurve] for the implicit widgets
///   (`AnimatedContainer` and friends), which retarget from the current value
///   but want a duration and a curve: the same spring laid over 1.5·T, by
///   which time a critically damped one has settled to within 0.1 %.
///
/// Bounce (ζ 0.8) belongs only after a gesture that carried momentum. Every
/// motion the interface starts by itself is critically damped.
abstract final class CommySprings {
  /// ζ 1.0, T 0.30 — a press, a switch, a segment, a checkbox.
  static const SpringDescription snappy =
      SpringDescription(mass: 1, stiffness: 438.65, damping: 41.89);

  /// ζ 1.0, T 0.40 — content changing, a screen transition.
  static const SpringDescription smooth =
      SpringDescription(mass: 1, stiffness: 246.74, damping: 31.42);

  /// ζ 1.0, T 0.35 — a row expanding, a chevron turning, a block's height.
  static const SpringDescription expand =
      SpringDescription(mass: 1, stiffness: 322.27, damping: 35.90);

  /// ζ 1.0, T 0.38 — a leg of the route drawn to its stop.
  static const SpringDescription land =
      SpringDescription(mass: 1, stiffness: 273.40, damping: 33.07);

  /// ζ 1.0, T 0.45 — a toast or a banner arriving and leaving.
  static const SpringDescription notify =
      SpringDescription(mass: 1, stiffness: 194.96, damping: 27.93);

  /// ζ 1.0, T 0.60 — a slow shift: the route changing colour.
  static const SpringDescription gentle =
      SpringDescription(mass: 1, stiffness: 109.66, damping: 20.94);

  /// ζ 1.0, T 0.32 — a stop of the route lighting up.
  static const SpringDescription materialize =
      SpringDescription(mass: 1, stiffness: 385.53, damping: 39.27);

  /// ζ 0.8, T 0.30 — a sheet after the finger lets go.
  static const SpringDescription sheet =
      SpringDescription(mass: 1, stiffness: 438.65, damping: 33.51);

  /// ζ 0.8, T 0.35 — the snap after a flick.
  static const SpringDescription flick =
      SpringDescription(mass: 1, stiffness: 322.27, damping: 28.72);

  /// How much longer than T an implicit animation runs: 1.5·T is where a
  /// critically damped spring is within 0.1 % of its target.
  static const double settleFactor = 1.5;

  /// The curve of a critically damped spring laid over `settleFactor · T`.
  ///
  /// Every implicit preset shares it: with the duration scaled to T, the
  /// normalised response is the same fraction, `1 / settleFactor`.
  static const CommySpringCurve curve = CommySpringCurve(
    dampingRatio: 1,
    response: 1 / settleFactor,
  );
}
