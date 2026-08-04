import 'package:commy_ui/src/tokens/spring_curve.dart';
import 'package:flutter/material.dart';

/// Motion tokens: five durations with the curve that belongs to each.
///
/// Two principles are baked into these numbers. Animation *explains* a change;
/// no explanation means no animation. And nothing lasts longer than 620 ms —
/// the app is opened to press one button.
///
/// `MediaQuery.disableAnimations` is honoured by every widget in this package:
/// the pulse, the arc rotation and the traffic redraw become instant state
/// changes. That is accessibility, not a preference.
@immutable
class CommyMotion extends ThemeExtension<CommyMotion> {
  /// Creates a motion set. Use [standard] unless a test needs otherwise.
  const CommyMotion({
    this.instant = const Duration(milliseconds: 90),
    this.instantCurve = Curves.easeOut,
    this.fast = const Duration(milliseconds: 140),
    this.fastCurve = Curves.easeOutCubic,
    this.base = const Duration(milliseconds: 220),
    this.baseCurve = Curves.easeOutCubic,
    this.slow = const Duration(milliseconds: 340),
    this.slowCurve = Curves.easeOutCubic,
    this.connect = const Duration(milliseconds: 620),
    this.connectCurve = const CommySpringCurve(),
    this.shimmer = const Duration(milliseconds: 1200),
    this.spinner = const Duration(milliseconds: 900),
  });

  /// The one and only motion set.
  static const CommyMotion standard = CommyMotion();

  /// A motion set with every duration collapsed to zero.
  ///
  /// What widgets fall back to under `MediaQuery.disableAnimations`, so that
  /// the reduced-motion path stays a single code path instead of a fork.
  static const CommyMotion none = CommyMotion(
    instant: Duration.zero,
    fast: Duration.zero,
    base: Duration.zero,
    slow: Duration.zero,
    connect: Duration.zero,
    shimmer: Duration.zero,
    spinner: Duration.zero,
  );

  /// `motion/instant` — 90 ms. Press, hover, chip.
  final Duration instant;

  /// Curve of [instant]: `easeOut`.
  final Curve instantCurve;

  /// `motion/fast` — 140 ms. Switch, checkbox, tooltip.
  final Duration fast;

  /// Curve of [fast]: `easeOutCubic`.
  final Curve fastCurve;

  /// `motion/base` — 220 ms. Screen transition, sheet entrance.
  final Duration base;

  /// Curve of [base]: `easeOutCubic`.
  final Curve baseCurve;

  /// `motion/slow` — 340 ms. Panel expansion, list reorder.
  final Duration slow;

  /// Curve of [slow]: `easeOutCubic`.
  final Curve slowCurve;

  /// `motion/connect` — 620 ms. Connection state change. The ceiling.
  final Duration connect;

  /// Curve of [connect]: a spring, 0.85 damping / 0.5 response.
  final Curve connectCurve;

  /// Period of the skeleton shimmer sweep.
  ///
  /// Not in the document's table: skeletons are a loading affordance rather
  /// than a state change, and they need a period of their own.
  final Duration shimmer;

  /// One full turn of the indeterminate spinner.
  ///
  /// Also not in the table, for the same reason: a spinner is a "still
  /// working" signal, not a transition between two states.
  final Duration spinner;

  /// Returns a copy with the given tokens replaced.
  @override
  CommyMotion copyWith({
    Duration? instant,
    Curve? instantCurve,
    Duration? fast,
    Curve? fastCurve,
    Duration? base,
    Curve? baseCurve,
    Duration? slow,
    Curve? slowCurve,
    Duration? connect,
    Curve? connectCurve,
    Duration? shimmer,
    Duration? spinner,
  }) {
    return CommyMotion(
      instant: instant ?? this.instant,
      instantCurve: instantCurve ?? this.instantCurve,
      fast: fast ?? this.fast,
      fastCurve: fastCurve ?? this.fastCurve,
      base: base ?? this.base,
      baseCurve: baseCurve ?? this.baseCurve,
      slow: slow ?? this.slow,
      slowCurve: slowCurve ?? this.slowCurve,
      connect: connect ?? this.connect,
      connectCurve: connectCurve ?? this.connectCurve,
      shimmer: shimmer ?? this.shimmer,
      spinner: spinner ?? this.spinner,
    );
  }

  /// Durations do not interpolate; the nearer set wins.
  @override
  CommyMotion lerp(covariant CommyMotion? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
