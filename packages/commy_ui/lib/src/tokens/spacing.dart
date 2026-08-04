import 'package:flutter/material.dart';

/// The 4 pt spacing scale. These eleven values are the only gaps that exist.
///
/// Anything not on this list is a bug (rule R4). Density: `s4` is the base
/// screen inset on mobile, `s6` on desktop.
@immutable
class CommySpacing extends ThemeExtension<CommySpacing> {
  /// Creates a spacing scale. Use [standard] unless a test needs otherwise.
  const CommySpacing({
    this.s0 = 0,
    this.s1 = 4,
    this.s2 = 8,
    this.s3 = 12,
    this.s4 = 16,
    this.s5 = 20,
    this.s6 = 24,
    this.s8 = 32,
    this.s10 = 40,
    this.s12 = 48,
    this.s16 = 64,
  });

  /// The one and only scale.
  static const CommySpacing standard = CommySpacing();

  /// `space/0` — 0.
  final double s0;

  /// `space/1` — 4.
  final double s1;

  /// `space/2` — 8.
  final double s2;

  /// `space/3` — 12.
  final double s3;

  /// `space/4` — 16. Base screen inset on mobile.
  final double s4;

  /// `space/5` — 20.
  final double s5;

  /// `space/6` — 24. Base screen inset on desktop.
  final double s6;

  /// `space/8` — 32.
  final double s8;

  /// `space/10` — 40.
  final double s10;

  /// `space/12` — 48.
  final double s12;

  /// `space/16` — 64.
  final double s16;

  /// Returns a copy with the given steps replaced.
  @override
  CommySpacing copyWith({
    double? s0,
    double? s1,
    double? s2,
    double? s3,
    double? s4,
    double? s5,
    double? s6,
    double? s8,
    double? s10,
    double? s12,
    double? s16,
  }) {
    return CommySpacing(
      s0: s0 ?? this.s0,
      s1: s1 ?? this.s1,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      s4: s4 ?? this.s4,
      s5: s5 ?? this.s5,
      s6: s6 ?? this.s6,
      s8: s8 ?? this.s8,
      s10: s10 ?? this.s10,
      s12: s12 ?? this.s12,
      s16: s16 ?? this.s16,
    );
  }

  /// The scale never animates; interpolation returns [other] or `this`.
  @override
  CommySpacing lerp(covariant CommySpacing? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
