import 'package:commy_ui/src/tokens/springs.dart';
import 'package:flutter/material.dart';

/// Durations and curves for the implicit animations
/// (docs/04-design-system.md §7).
///
/// Every curve but one is a critically damped spring ([CommySprings.curve])
/// laid over 1.5 × its T, so `AnimatedContainer` and friends move the way the
/// interactive springs do and still retarget from the value on screen. The
/// exception is [instant]: a colour under a finger or a pointer, which is the
/// one place the protocol keeps a plain transition.
///
/// `MediaQuery.disableAnimations` and the app's own "reduce motion" switch
/// both collapse this set to [none] — springs and travelling highlights become
/// instant state changes. That is accessibility, not a preference.
@immutable
class CommyMotion extends ThemeExtension<CommyMotion> {
  /// Creates a motion set. Use [standard] unless a test needs otherwise.
  const CommyMotion({
    this.instant = const Duration(milliseconds: 100),
    this.instantCurve = Curves.easeOut,
    this.fast = const Duration(milliseconds: 450),
    this.fastCurve = CommySprings.curve,
    this.base = const Duration(milliseconds: 600),
    this.baseCurve = CommySprings.curve,
    this.slow = const Duration(milliseconds: 525),
    this.slowCurve = CommySprings.curve,
    this.notify = const Duration(milliseconds: 675),
    this.land = const Duration(milliseconds: 570),
    this.materialize = const Duration(milliseconds: 480),
    this.gentle = const Duration(milliseconds: 900),
    this.springCurve = CommySprings.curve,
    this.sweep = const Duration(milliseconds: 1200),
    this.stagger = const Duration(milliseconds: 50),
    this.skeletonDelay = const Duration(milliseconds: 300),
    this.shimmer = const Duration(milliseconds: 1200),
    this.spinner = const Duration(milliseconds: 900),
  });

  /// The one and only motion set.
  static const CommyMotion standard = CommyMotion();

  /// A motion set with every duration collapsed to zero.
  ///
  /// What widgets fall back to when motion is reduced, so that the reduced
  /// path stays a single code path instead of a fork. §7.4 allows a colour
  /// change of up to 120 ms there; zero is the end of that range that keeps
  /// every state change a single frame.
  static const CommyMotion none = CommyMotion(
    instant: Duration.zero,
    fast: Duration.zero,
    base: Duration.zero,
    slow: Duration.zero,
    notify: Duration.zero,
    land: Duration.zero,
    materialize: Duration.zero,
    gentle: Duration.zero,
    sweep: Duration.zero,
    stagger: Duration.zero,
    shimmer: Duration.zero,
    spinner: Duration.zero,
  );

  /// 100 ms — the colour of a press or a hover, the scroll-edge hairline.
  final Duration instant;

  /// Curve of [instant]: `easeOut`.
  final Curve instantCurve;

  /// `snappy` (ζ 1, T 0.30) laid over 450 ms — a switch, a checkbox, a
  /// segment's thumb.
  final Duration fast;

  /// Curve of [fast]: the spring.
  final Curve fastCurve;

  /// `smooth` (ζ 1, T 0.40) laid over 600 ms — content changing, a sheet
  /// arriving.
  final Duration base;

  /// Curve of [base]: the spring.
  final Curve baseCurve;

  /// `expand` (ζ 1, T 0.35) laid over 525 ms — a block growing, a chevron.
  final Duration slow;

  /// Curve of [slow]: the spring.
  final Curve slowCurve;

  /// `notify` (ζ 1, T 0.45) laid over 675 ms — a toast or a banner.
  final Duration notify;

  /// `land` (ζ 1, T 0.38) laid over 570 ms — a leg of the route drawn to its
  /// stop.
  final Duration land;

  /// `materialize` (ζ 1, T 0.32) laid over 480 ms — a stop lighting up.
  final Duration materialize;

  /// `gentle` (ζ 1, T 0.60) laid over 900 ms — the route changing colour.
  final Duration gentle;

  /// The curve every spring-backed duration above runs on.
  final Curve springCurve;

  /// One pass of the highlight travelling along a leg of the route that is
  /// still being built: 0.83 Hz, well away from the slow oscillations around
  /// 0.2 Hz that reduced-motion guidance warns about.
  final Duration sweep;

  /// Delay between elements that appear together, at most three or four.
  final Duration stagger;

  /// How long a load may take before its skeleton is shown at all — a
  /// skeleton that flashes for a frame is worse than none.
  final Duration skeletonDelay;

  /// Period of the skeleton shimmer sweep.
  final Duration shimmer;

  /// One full turn of the indeterminate spinner.
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
    Duration? notify,
    Duration? land,
    Duration? materialize,
    Duration? gentle,
    Curve? springCurve,
    Duration? sweep,
    Duration? stagger,
    Duration? skeletonDelay,
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
      notify: notify ?? this.notify,
      land: land ?? this.land,
      materialize: materialize ?? this.materialize,
      gentle: gentle ?? this.gentle,
      springCurve: springCurve ?? this.springCurve,
      sweep: sweep ?? this.sweep,
      stagger: stagger ?? this.stagger,
      skeletonDelay: skeletonDelay ?? this.skeletonDelay,
      shimmer: shimmer ?? this.shimmer,
      spinner: spinner ?? this.spinner,
    );
  }

  /// Durations do not interpolate; the nearer set wins.
  @override
  CommyMotion lerp(covariant CommyMotion? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
