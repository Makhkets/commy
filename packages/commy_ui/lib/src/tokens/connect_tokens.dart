import 'package:flutter/material.dart';

/// Geometry and the derived colours of the connect button.
///
/// The connect button is the only place in the product where a glow is
/// allowed, and the only component whose spec table names colours that are
/// not in the semantic set — `status/connected` at 6 %, at 9 %, at 60 %, and
/// `status/error` at 7 %. Those four live here, pre-multiplied, so that the
/// widget file stays free of literals (rule R4).
///
/// The geometry is the spec table of docs/04-design-system.md verbatim:
/// 240 dp container, Ø208 halo, Ø172 disc, 62 dp power glyph on a 2.2 stroke.
@immutable
class CommyConnectTokens extends ThemeExtension<CommyConnectTokens> {
  /// Creates a set. Use [dark] or [light].
  const CommyConnectTokens({
    required this.haloChecking,
    required this.haloConnected,
    required this.haloError,
    required this.glyphChecking,
  });

  /// Outer diameter of the whole component, including the halo's breathing
  /// room — 240.
  static const double containerSize = 240;

  /// Diameter of the halo — 208.
  static const double haloSize = 208;

  /// Diameter of the disc, which is also the tap target — 172.
  static const double discSize = 172;

  /// Side of the power glyph — 62.
  static const double glyphSize = 62;

  /// Stroke of the power glyph — 2.2. An icon font cannot do this, which is
  /// why the glyph is painted rather than drawn from Lucide.
  static const double glyphStroke = 2.2;

  /// Sweep of the `starting` progress arc, in degrees — 270.
  static const double startingArcSweep = 270;

  /// Sweep of the shorter `checking` probe arc, in degrees — 90.
  static const double checkingArcSweep = 90;

  /// One full turn of the progress arc — 900 ms, linear.
  static const Duration arcRotation = Duration(milliseconds: 900);

  /// One full breath of the connected glow — 2.4 s.
  static const Duration pulsePeriod = Duration(milliseconds: 2400);

  /// Dimmest the glow gets at the bottom of the pulse — 0.55.
  static const double pulseMinIntensity = 0.55;

  /// Blur of the glow shadow — 40.
  static const double glowBlur = 40;

  /// Spread of the glow shadow — 6.
  static const double glowSpread = 6;

  /// Dark theme values.
  static const CommyConnectTokens dark = CommyConnectTokens(
    haloChecking: Color(0x0F2FD98A),
    haloConnected: Color(0x172FD98A),
    haloError: Color(0x12F76C6C),
    glyphChecking: Color(0x992FD98A),
  );

  /// Light theme values.
  static const CommyConnectTokens light = CommyConnectTokens(
    haloChecking: Color(0x0F0C7A4A),
    haloConnected: Color(0x170C7A4A),
    haloError: Color(0x12A02020),
    glyphChecking: Color(0x990C7A4A),
  );

  /// Halo while checking: `status/connected` at 6 %.
  final Color haloChecking;

  /// Halo while connected: `status/connected` at 9 %.
  final Color haloConnected;

  /// Halo while errored: `status/error` at 7 %.
  final Color haloError;

  /// Power glyph while checking: `status/connected` at 60 %.
  final Color glyphChecking;

  /// Returns a copy with the given colours replaced.
  @override
  CommyConnectTokens copyWith({
    Color? haloChecking,
    Color? haloConnected,
    Color? haloError,
    Color? glyphChecking,
  }) {
    return CommyConnectTokens(
      haloChecking: haloChecking ?? this.haloChecking,
      haloConnected: haloConnected ?? this.haloConnected,
      haloError: haloError ?? this.haloError,
      glyphChecking: glyphChecking ?? this.glyphChecking,
    );
  }

  /// Interpolates towards [other].
  @override
  CommyConnectTokens lerp(covariant CommyConnectTokens? other, double t) {
    if (other == null) {
      return this;
    }
    return CommyConnectTokens(
      haloChecking: Color.lerp(haloChecking, other.haloChecking, t)!,
      haloConnected: Color.lerp(haloConnected, other.haloConnected, t)!,
      haloError: Color.lerp(haloError, other.haloError, t)!,
      glyphChecking: Color.lerp(glyphChecking, other.glyphChecking, t)!,
    );
  }
}
