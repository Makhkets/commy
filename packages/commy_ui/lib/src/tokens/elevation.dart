import 'package:flutter/material.dart';

/// Shadows — only on what floats (docs/04-design-system.md §5).
///
/// Cards and grouped lists carry none in either theme: the step from the grey
/// canvas to the white or `#1C1C1E` surface is what separates them, and a soft
/// shadow under every card is one of the commonest marks of a generated
/// interface. What floats above the content — a sheet, a dialog, a menu, a
/// toast, the thumb of a switch — casts one in the light theme. In the dark
/// one a shadow does not read against black; the border takes its place, and
/// the sets below are empty.
@immutable
class CommyElevation extends ThemeExtension<CommyElevation> {
  /// Creates an elevation set. Use [dark] or [light].
  const CommyElevation({
    required this.level1,
    required this.level2,
    required this.level3,
    required this.thumb,
  });

  /// Dark theme: no shadows at all; floating surfaces take a border instead.
  static const CommyElevation dark = CommyElevation(
    level1: <BoxShadow>[],
    level2: <BoxShadow>[],
    level3: <BoxShadow>[],
    thumb: <BoxShadow>[],
  );

  /// Light theme: nothing under a card, `0 8 24 / 12 %` under a sheet,
  /// `0 12 32 / 16 %` under a menu or a toast, and the small double shadow
  /// iOS gives a switch's thumb.
  static const CommyElevation light = CommyElevation(
    level1: <BoxShadow>[],
    level2: <BoxShadow>[
      BoxShadow(
        color: Color(0x1F000000),
        offset: Offset(0, 8),
        blurRadius: 24,
      ),
    ],
    level3: <BoxShadow>[
      BoxShadow(
        color: Color(0x29000000),
        offset: Offset(0, 12),
        blurRadius: 32,
      ),
    ],
    thumb: <BoxShadow>[
      BoxShadow(
        color: Color(0x26000000),
        offset: Offset(0, 2),
        blurRadius: 6,
      ),
      BoxShadow(
        color: Color(0x0A000000),
        spreadRadius: 0.5,
      ),
    ],
  );

  /// A card on the canvas: nothing, in both themes.
  final List<BoxShadow> level1;

  /// A sheet or a dialog.
  final List<BoxShadow> level2;

  /// A menu or a toast, above a sheet.
  final List<BoxShadow> level3;

  /// The thumb of a switch or a segmented control, riding on its track.
  final List<BoxShadow> thumb;

  /// Returns a copy with the given levels replaced.
  @override
  CommyElevation copyWith({
    List<BoxShadow>? level1,
    List<BoxShadow>? level2,
    List<BoxShadow>? level3,
    List<BoxShadow>? thumb,
  }) {
    return CommyElevation(
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
      thumb: thumb ?? this.thumb,
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
      thumb: BoxShadow.lerpList(thumb, other.thumb, t) ?? none,
    );
  }
}
