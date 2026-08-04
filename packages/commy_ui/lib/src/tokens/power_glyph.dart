/// Path metrics of the power sign drawn inside the connect button.
///
/// The glyph is painted rather than taken from `lucide_icons_flutter` for one
/// reason: docs/04-design-system.md pins its stroke at 2.2, and an icon font
/// carries the stroke baked into the outline — asking for 62 dp of Lucide
/// `power` gives a 4.5 dp stroke, which reads as a toy.
///
/// The numbers below are Lucide's own `power` path, unchanged, expressed in
/// its 24-unit design grid: a bar from (12, 2) to (12, 12), and a circle of
/// radius 9 about (12, 13) that is open for 90° at the top. They live in
/// `tokens/` because rule R4 leaves no other place for a bare number, and they
/// belong next to the rest of the connect geometry rather than inside the
/// painter.
abstract final class CommyPowerGlyph {
  /// Side of Lucide's design grid — 24. Everything below is in these units.
  static const double grid = 24;

  /// Horizontal axis of the glyph: the bar and the circle share it — 12.
  static const double centerX = 12;

  /// Vertical centre of the circle — 13, one unit below the grid centre.
  static const double arcCenterY = 13;

  /// Radius of the circle — 9.
  static const double arcRadius = 9;

  /// Where the bar starts — 2.
  static const double barTopY = 2;

  /// Where the bar ends — 12, just above the circle's centre.
  static const double barBottomY = 12;

  /// Where the circle starts, in degrees clockwise from three o'clock — −45.
  static const double arcStartDegrees = -45;

  /// How far the circle is drawn, in degrees — 270, leaving the bar a gap.
  static const double arcSweepDegrees = 270;
}
