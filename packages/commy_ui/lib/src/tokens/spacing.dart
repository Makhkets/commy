import 'package:flutter/material.dart';

/// The 4 dp spacing scale. These fourteen values are the only gaps that
/// exist — docs/04-design-system.md §4: 2, 4, 6, 8, 12, 16, 20, 24, 32, 40,
/// 48, 64, 80, 96.
///
/// Anything not on this list is a bug (rule R4). The name is the step on the
/// 4 dp grid: `s4` is 4 × 4 = 16, and the two half steps are `s05` (2) and
/// `s15` (6).
@immutable
class CommySpacing extends ThemeExtension<CommySpacing> {
  /// Creates a spacing scale. Use [standard] unless a test needs otherwise.
  const CommySpacing({
    this.s0 = 0,
    this.s05 = 2,
    this.s1 = 4,
    this.s15 = 6,
    this.s2 = 8,
    this.s3 = 12,
    this.s4 = 16,
    this.s5 = 20,
    this.s6 = 24,
    this.s8 = 32,
    this.s10 = 40,
    this.s12 = 48,
    this.s16 = 64,
    this.s20 = 80,
    this.s24 = 96,
  });

  /// The one and only scale.
  static const CommySpacing standard = CommySpacing();

  /// 0.
  final double s0;

  /// 2. A hairline's worth: a badge's inner vertical gap.
  final double s05;

  /// 4.
  final double s1;

  /// 6. The gap between the words of a server's protocol line.
  final double s15;

  /// 8. Section header to its content on a phone.
  final double s2;

  /// 12. Between cards on a phone; a list row's vertical padding.
  final double s3;

  /// 16. Screen inset and card padding on a phone; a row's side padding.
  final double s4;

  /// 20. Card padding from 1024 dp up.
  final double s5;

  /// 24. Between sections on a phone.
  final double s6;

  /// 32. Between sections, and the screen inset, from 1024 dp up.
  final double s8;

  /// 40. Screen inset from 1440 dp up.
  final double s10;

  /// 48.
  final double s12;

  /// 64.
  final double s16;

  /// 80.
  final double s20;

  /// 96.
  final double s24;

  /// Returns a copy with the given steps replaced.
  @override
  CommySpacing copyWith({
    double? s0,
    double? s05,
    double? s1,
    double? s15,
    double? s2,
    double? s3,
    double? s4,
    double? s5,
    double? s6,
    double? s8,
    double? s10,
    double? s12,
    double? s16,
    double? s20,
    double? s24,
  }) {
    return CommySpacing(
      s0: s0 ?? this.s0,
      s05: s05 ?? this.s05,
      s1: s1 ?? this.s1,
      s15: s15 ?? this.s15,
      s2: s2 ?? this.s2,
      s3: s3 ?? this.s3,
      s4: s4 ?? this.s4,
      s5: s5 ?? this.s5,
      s6: s6 ?? this.s6,
      s8: s8 ?? this.s8,
      s10: s10 ?? this.s10,
      s12: s12 ?? this.s12,
      s16: s16 ?? this.s16,
      s20: s20 ?? this.s20,
      s24: s24 ?? this.s24,
    );
  }

  /// The scale never animates; interpolation returns [other] or `this`.
  @override
  CommySpacing lerp(covariant CommySpacing? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
