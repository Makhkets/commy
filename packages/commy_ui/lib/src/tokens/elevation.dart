import 'package:flutter/material.dart';

/// Elevation, expressed the way the dark theme actually works.
///
/// On graphite, shadows barely read. Hierarchy is built by raising the
/// background and adding a border, which is why the dark set below is empty
/// at every level. The light theme keeps real shadows, since a white surface
/// on a near-white canvas has nothing else to separate it.
@immutable
class CommyElevation extends ThemeExtension<CommyElevation> {
  /// Creates an elevation set. Use [dark] or [light].
  const CommyElevation({
    required this.level1,
    required this.level2,
    required this.level3,
  });

  /// Dark theme: no shadows at all, by design.
  static const CommyElevation dark = CommyElevation(
    level1: <BoxShadow>[],
    level2: <BoxShadow>[],
    level3: <BoxShadow>[],
  );

  /// Light theme: `0 1 2 / 6%`, `0 8 24 / 14%`, `0 16 40 / 20%`.
  static const CommyElevation light = CommyElevation(
    level1: <BoxShadow>[
      BoxShadow(
        color: Color(0x0F131519),
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
    level2: <BoxShadow>[
      BoxShadow(
        color: Color(0x24131519),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    level3: <BoxShadow>[
      BoxShadow(
        color: Color(0x33131519),
        offset: Offset(0, 16),
        blurRadius: 40,
      ),
    ],
  );

  /// Level 1 — a card sitting on the canvas.
  final List<BoxShadow> level1;

  /// Level 2 — a sheet or dialog.
  final List<BoxShadow> level2;

  /// Level 3 — a popup or menu above a sheet.
  final List<BoxShadow> level3;

  /// Returns a copy with the given levels replaced.
  @override
  CommyElevation copyWith({
    List<BoxShadow>? level1,
    List<BoxShadow>? level2,
    List<BoxShadow>? level3,
  }) {
    return CommyElevation(
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
    );
  }

  /// Interpolates towards [other].
  @override
  CommyElevation lerp(covariant CommyElevation? other, double t) {
    if (other == null) {
      return this;
    }
    const none = <BoxShadow>[];
    return CommyElevation(
      level1: BoxShadow.lerpList(level1, other.level1, t) ?? none,
      level2: BoxShadow.lerpList(level2, other.level2, t) ?? none,
      level3: BoxShadow.lerpList(level3, other.level3, t) ?? none,
    );
  }
}
