import 'package:flutter/material.dart';

/// Corner radii. Deliberately larger than the usual draft values: small radii
/// read as "system shape, 2015".
@immutable
class CommyRadii extends ThemeExtension<CommyRadii> {
  /// Creates a radius scale. Use [standard] unless a test needs otherwise.
  const CommyRadii({
    this.xs = 8,
    this.sm = 12,
    this.md = 18,
    this.lg = 24,
    this.xl = 32,
    this.full = 999,
    this.flag = 5,
  });

  /// The one and only scale.
  static const CommyRadii standard = CommyRadii();

  /// `radius/xs` — 8. Badge, latency chip.
  final double xs;

  /// `radius/sm` — 12. Button, input field, secondary action.
  final double sm;

  /// `radius/md` — 18. Card, list row, row group.
  final double md;

  /// `radius/lg` — 24. Bottom sheet, dialog, profile card.
  final double lg;

  /// `radius/xl` — 32. Hero card.
  final double xl;

  /// `radius/full` — 999. Pill, chip, avatar, ring.
  final double full;

  /// Corner of the vector country flag, 5. Not part of the public scale: it
  /// belongs to one component and exists here only so the painter stays free
  /// of literals.
  final double flag;

  /// [xs] as a symmetric [BorderRadius].
  BorderRadius get xsAll => BorderRadius.circular(xs);

  /// [sm] as a symmetric [BorderRadius].
  BorderRadius get smAll => BorderRadius.circular(sm);

  /// [md] as a symmetric [BorderRadius].
  BorderRadius get mdAll => BorderRadius.circular(md);

  /// [lg] as a symmetric [BorderRadius].
  BorderRadius get lgAll => BorderRadius.circular(lg);

  /// [xl] as a symmetric [BorderRadius].
  BorderRadius get xlAll => BorderRadius.circular(xl);

  /// [full] as a symmetric [BorderRadius].
  BorderRadius get fullAll => BorderRadius.circular(full);

  /// [lg] applied to the top corners only — the bottom sheet shape.
  BorderRadius get lgTop => BorderRadius.vertical(top: Radius.circular(lg));

  /// Returns a copy with the given radii replaced.
  @override
  CommyRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? full,
    double? flag,
  }) {
    return CommyRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      full: full ?? this.full,
      flag: flag ?? this.flag,
    );
  }

  /// The scale never animates; interpolation returns [other] or `this`.
  @override
  CommyRadii lerp(covariant CommyRadii? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
