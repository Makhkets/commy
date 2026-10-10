import 'package:commy_ui/src/tokens/colors.dart';
import 'package:flutter/material.dart';

/// The hue a tag on a server row is drawn in.
///
/// Hue names, not meanings: which protocol wears which hue is the app's
/// decision (`NodeDescriptors`), recorded in docs/04-design-system.md, "Метки
/// сервера". [neutral] is the caption colour the line had before it had any
/// colour at all, and is what a transport and anything unknown get.
enum CommyTagHue {
  /// No hue: `text/secondary`.
  neutral,

  /// Blue. VLESS.
  azure,

  /// Lighter, greener blue. VMess — the other half of the V2Ray family.
  sky,

  /// Violet. Reality.
  iris,

  /// Pink-violet. Trojan.
  orchid,

  /// Blue-green. The Shadowsocks family.
  teal,

  /// Orange. The QUIC protocols, Hysteria 2 and TUIC.
  tangerine,

  /// Red-orange. WireGuard.
  coral,

  /// Green. TLS.
  mint,

  /// Yellow. The XTLS flow, Vision.
  gold,
}

/// Colours of the protocol tags on a server row: `VLESS · Reality · TCP`.
///
/// The one place colour in this product says something other than connection
/// state, and it was the owner's call (2026-10-10, after INCY): a list of
/// near-identical names reads faster when the protocol under each one is a
/// colour as well as a word. It stays a second channel — the word is always
/// there, and a server that stopped answering loses every hue and goes grey.
///
/// Each value clears WCAG AA (4.5:1) for caption text on every ground a row
/// is drawn on — `bg/surface`, `bg/raised` of the picker sheet, the tile's
/// `bg/overlay`, the connected wash of the active row over both, and the
/// `accent/wash` of a pointer hovering an ordinary row — in its own theme.
/// Keyboard focus is a ring, not a fill, and the plate takes no hover wash,
/// so nothing else ever lands under the words. `test/tokens/contrast_test.dart`
/// holds that, and the table in docs/04 lists the figures. Dark values sit at
/// the 400 step of their ramp, light ones at 700–800, the same rule as the
/// status hues.
@immutable
class CommyTagColors extends ThemeExtension<CommyTagColors> {
  /// Creates a set. Use [dark] or [light].
  const CommyTagColors({
    required this.azure,
    required this.sky,
    required this.iris,
    required this.orchid,
    required this.teal,
    required this.tangerine,
    required this.coral,
    required this.mint,
    required this.gold,
  });

  /// The dark theme.
  static const CommyTagColors dark = CommyTagColors(
    azure: Color(0xFF63A8FF),
    sky: Color(0xFF38BDF8),
    iris: Color(0xFFA78BFA),
    orchid: Color(0xFFE879F9),
    teal: Color(0xFF2DD4BF),
    tangerine: Color(0xFFFB923C),
    coral: Color(0xFFFF8A7A),
    mint: Color(0xFF4ADE80),
    gold: Color(0xFFF4C542),
  );

  /// The light theme.
  static const CommyTagColors light = CommyTagColors(
    azure: Color(0xFF1D4FD8),
    sky: Color(0xFF0369A1),
    iris: Color(0xFF6D28D9),
    orchid: Color(0xFFA21CAF),
    teal: Color(0xFF0E7068),
    tangerine: Color(0xFFB2400E),
    coral: Color(0xFFBE123C),
    mint: Color(0xFF11753A),
    gold: Color(0xFF8A5A00),
  );

  /// VLESS.
  final Color azure;

  /// VMess.
  final Color sky;

  /// Reality.
  final Color iris;

  /// Trojan.
  final Color orchid;

  /// Shadowsocks and ShadowTLS.
  final Color teal;

  /// Hysteria 2 and TUIC.
  final Color tangerine;

  /// WireGuard.
  final Color coral;

  /// TLS.
  final Color mint;

  /// Vision.
  final Color gold;

  /// The colour of [hue]. [CommyTagHue.neutral] is `text/secondary` of
  /// [colors], so a tag without a hue looks exactly like the caption it is.
  Color of(CommyTagHue hue, CommyColors colors) => switch (hue) {
        CommyTagHue.neutral => colors.textSecondary,
        CommyTagHue.azure => azure,
        CommyTagHue.sky => sky,
        CommyTagHue.iris => iris,
        CommyTagHue.orchid => orchid,
        CommyTagHue.teal => teal,
        CommyTagHue.tangerine => tangerine,
        CommyTagHue.coral => coral,
        CommyTagHue.mint => mint,
        CommyTagHue.gold => gold,
      };

  /// Returns a copy with the given colours replaced.
  @override
  CommyTagColors copyWith({
    Color? azure,
    Color? sky,
    Color? iris,
    Color? orchid,
    Color? teal,
    Color? tangerine,
    Color? coral,
    Color? mint,
    Color? gold,
  }) {
    return CommyTagColors(
      azure: azure ?? this.azure,
      sky: sky ?? this.sky,
      iris: iris ?? this.iris,
      orchid: orchid ?? this.orchid,
      teal: teal ?? this.teal,
      tangerine: tangerine ?? this.tangerine,
      coral: coral ?? this.coral,
      mint: mint ?? this.mint,
      gold: gold ?? this.gold,
    );
  }

  /// Interpolates towards [other]. Used when the theme animates.
  @override
  CommyTagColors lerp(covariant CommyTagColors? other, double t) {
    if (other == null) {
      return this;
    }
    return CommyTagColors(
      azure: Color.lerp(azure, other.azure, t)!,
      sky: Color.lerp(sky, other.sky, t)!,
      iris: Color.lerp(iris, other.iris, t)!,
      orchid: Color.lerp(orchid, other.orchid, t)!,
      teal: Color.lerp(teal, other.teal, t)!,
      tangerine: Color.lerp(tangerine, other.tangerine, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
    );
  }
}
