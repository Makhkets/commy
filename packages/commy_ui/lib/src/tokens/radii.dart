import 'package:flutter/material.dart';

/// Corner radii, growing with the surface they round
/// (docs/04-design-system.md §5): the bigger the surface, the bigger the
/// radius. A nested element takes `outer − inset`, so a 16 dp plate sits in
/// a 20 dp card inset by 4.
@immutable
class CommyRadii extends ThemeExtension<CommyRadii> {
  /// Creates a radius scale. Use [standard] unless a test needs otherwise.
  const CommyRadii({
    this.xs = 6,
    this.sm = 10,
    this.control = 14,
    this.block = 16,
    this.card = 20,
    this.tile = 24,
    this.plate = 28,
    this.pill = 999,
    this.flag = 4,
  });

  /// The one and only scale.
  static const CommyRadii standard = CommyRadii();

  /// 6. A badge, a highlight inside a row.
  final double xs;

  /// 10. A flag tile, a segment's thumb, a mini block.
  final double sm;

  /// 14. A button, a field, the search field, the segment track.
  final double control;

  /// 16. A toast, a banner, the plate of the active server (`card − 4`).
  final double block;

  /// 20. A card, a grouped list.
  final double card;

  /// 24. The large tiles of the first run.
  final double tile;

  /// 28. The top of a sheet, a dialog.
  final double plate;

  /// 999. A chip, a switch, a dot of the route.
  final double pill;

  /// Corner of the vector country flag, 4. Not part of the public scale: it
  /// belongs to one component and exists here only so the painter stays free
  /// of literals.
  final double flag;

  /// [xs] as a symmetric [BorderRadius].
  BorderRadius get xsAll => BorderRadius.circular(xs);

  /// [sm] as a symmetric [BorderRadius].
  BorderRadius get smAll => BorderRadius.circular(sm);

  /// [control] as a symmetric [BorderRadius].
  BorderRadius get controlAll => BorderRadius.circular(control);

  /// [block] as a symmetric [BorderRadius].
  BorderRadius get blockAll => BorderRadius.circular(block);

  /// [card] as a symmetric [BorderRadius].
  BorderRadius get cardAll => BorderRadius.circular(card);

  /// [tile] as a symmetric [BorderRadius].
  BorderRadius get tileAll => BorderRadius.circular(tile);

  /// [plate] as a symmetric [BorderRadius].
  BorderRadius get plateAll => BorderRadius.circular(plate);

  /// [pill] as a symmetric [BorderRadius].
  BorderRadius get pillAll => BorderRadius.circular(pill);

  /// [plate] on the top corners only — the bottom sheet's shape.
  BorderRadius get plateTop =>
      BorderRadius.vertical(top: Radius.circular(plate));

  /// Returns a copy with the given radii replaced.
  @override
  CommyRadii copyWith({
    double? xs,
    double? sm,
    double? control,
    double? block,
    double? card,
    double? tile,
    double? plate,
    double? pill,
    double? flag,
  }) {
    return CommyRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      control: control ?? this.control,
      block: block ?? this.block,
      card: card ?? this.card,
      tile: tile ?? this.tile,
      plate: plate ?? this.plate,
      pill: pill ?? this.pill,
      flag: flag ?? this.flag,
    );
  }

  /// The scale never animates; interpolation returns [other] or `this`.
  @override
  CommyRadii lerp(covariant CommyRadii? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}
