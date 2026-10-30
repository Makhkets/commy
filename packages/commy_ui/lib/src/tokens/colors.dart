import 'package:flutter/material.dart';

/// Semantic colour tokens of the "Route" system.
///
/// This class is the whole colour vocabulary of the product. The roles are
/// the ones docs/04-design-system.md §2 lists — canvas, surface, fill, ink,
/// line, action, the statuses — under the Dart names the code has always
/// used: `canvas` is [bgCanvas], `ink-2` is [textSecondary], `action` is
/// [accentSolid]. The table in §2.1 is the dictionary between the two. Rule
/// R4 — nothing outside `lib/src/tokens/` may write a colour literal.
///
/// The base is Apple's grouped palette — a grey canvas under white cards in
/// light, true black under `#1C1C1E` in dark — with the secondary and
/// tertiary inks taken darker (light) and lighter (dark) than Apple's, whose
/// values fall under 4.5:1 on their own grounds.
///
/// Every status comes in three: the colour for words and icons (4.5:1 and
/// up), a `…Solid` for lines, dots and fills under text (3:1 and up against
/// the canvas), and the `…OnSolid` drawn on top of that fill.
///
/// Alpha-bearing tokens are pre-multiplied here instead of being produced with
/// `withOpacity` at the call site: the value has to be identical in every
/// theme, and a const `Color` is the only way to guarantee that.
@immutable
class CommyColors extends ThemeExtension<CommyColors> {
  /// Creates a colour set. Use [dark] or [light]; build a new one only in
  /// tests.
  const CommyColors({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgRaised,
    required this.bgOverlay,
    required this.bgInset,
    required this.bgScrim,
    required this.fill,
    required this.fillStrong,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.focusRing,
    required this.thumb,
    required this.segmentThumb,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textInverse,
    required this.accentSolid,
    required this.accentHover,
    required this.accentOnSolid,
    required this.accentWash,
    required this.statusConnected,
    required this.statusConnecting,
    required this.statusError,
    required this.statusInfo,
    required this.statusIdle,
    required this.statusConnectedSolid,
    required this.statusConnectingSolid,
    required this.statusErrorSolid,
    required this.statusInfoSolid,
    required this.statusIdleSolid,
    required this.statusConnectedOnSolid,
    required this.statusConnectingOnSolid,
    required this.statusErrorOnSolid,
    required this.statusInfoOnSolid,
    required this.statusIdleOnSolid,
    required this.statusConnectedWash,
    required this.statusConnectingWash,
    required this.statusErrorWash,
    required this.statusInfoWash,
    required this.statusIdleWash,
  });

  /// Fully transparent. Exists so that no widget has to reach for
  /// `Colors.transparent`, which rule R4 forbids outside this directory.
  static const Color transparent = Color(0x00000000);

  /// The dark theme: true black under `#1C1C1E` cards, as iOS draws it.
  static const CommyColors dark = CommyColors(
    bgCanvas: Color(0xFF000000),
    bgSurface: Color(0xFF1C1C1E),
    // A sheet in dark is the colour of a card, the way iOS raises it: a
    // lighter sheet would drop the protocol tags on the active server's
    // plate under 4.5:1.
    bgRaised: Color(0xFF1C1C1E),
    bgOverlay: Color(0xFF2C2C2E),
    bgInset: Color(0xFF000000),
    bgScrim: Color(0x99000000),
    fill: Color(0x3D787880),
    fillStrong: Color(0x5C787880),
    borderSubtle: Color(0xFF38383A),
    borderDefault: Color(0xFF48484A),
    // 3:1 against the fill of a track, which is lighter than the card.
    borderStrong: Color(0xFF7E7E84),
    focusRing: Color(0xFFFFFFFF),
    thumb: Color(0xFFFFFFFF),
    segmentThumb: Color(0xFF636366),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFB5B5BB),
    textTertiary: Color(0xFF9C9CA2),
    textDisabled: Color(0xFF636366),
    textInverse: Color(0xFF000000),
    accentSolid: Color(0xFFFFFFFF),
    accentHover: Color(0xFFD1D1D6),
    accentOnSolid: Color(0xFF000000),
    accentWash: Color(0x14FFFFFF),
    statusConnected: Color(0xFF2FD98A),
    statusConnecting: Color(0xFFF5B547),
    statusError: Color(0xFFFF7A70),
    statusInfo: Color(0xFF64A8FF),
    statusIdle: Color(0xFF9C9CA2),
    statusConnectedSolid: Color(0xFF2FD98A),
    statusConnectingSolid: Color(0xFFF5B547),
    // Darker than the words: white has to read on it at 4.5:1.
    statusErrorSolid: Color(0xFFD93A3A),
    statusInfoSolid: Color(0xFF64A8FF),
    statusIdleSolid: Color(0xFF77777D),
    statusConnectedOnSolid: Color(0xFF000000),
    statusConnectingOnSolid: Color(0xFF000000),
    statusErrorOnSolid: Color(0xFFFFFFFF),
    statusInfoOnSolid: Color(0xFF000000),
    statusIdleOnSolid: Color(0xFF000000),
    statusConnectedWash: Color(0x242FD98A),
    statusConnectingWash: Color(0x24F5B547),
    statusErrorWash: Color(0x24FF7A70),
    statusInfoWash: Color(0x2464A8FF),
    statusIdleWash: Color(0x249C9CA2),
  );

  /// The light theme: white cards on Apple's grouped grey.
  static const CommyColors light = CommyColors(
    bgCanvas: Color(0xFFF2F2F7),
    bgSurface: Color(0xFFFFFFFF),
    bgRaised: Color(0xFFFFFFFF),
    bgOverlay: Color(0xFFE9E9EF),
    bgInset: Color(0xFFF2F2F7),
    bgScrim: Color(0x66000000),
    fill: Color(0x1F787880),
    fillStrong: Color(0x33787880),
    borderSubtle: Color(0xFFD8D8DD),
    borderDefault: Color(0xFFC6C6C8),
    borderStrong: Color(0xFF7C7C82),
    focusRing: Color(0xFF000000),
    thumb: Color(0xFFFFFFFF),
    segmentThumb: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF4A4A50),
    // Darker than Apple's tertiary label, which is 2:1: this one holds 4.5:1
    // on every ground it is drawn on, the search field's fill included.
    textTertiary: Color(0xFF626268),
    textDisabled: Color(0xFFAEAEB2),
    textInverse: Color(0xFFFFFFFF),
    accentSolid: Color(0xFF000000),
    accentHover: Color(0xFF2C2C2E),
    accentOnSolid: Color(0xFFFFFFFF),
    accentWash: Color(0x0D000000),
    statusConnected: Color(0xFF0B7546),
    statusConnecting: Color(0xFF8A4B00),
    statusError: Color(0xFFB42318),
    statusInfo: Color(0xFF1F5BD8),
    statusIdle: Color(0xFF626268),
    statusConnectedSolid: Color(0xFF159555),
    statusConnectingSolid: Color(0xFFB26A00),
    statusErrorSolid: Color(0xFFD92D20),
    statusInfoSolid: Color(0xFF1F5BD8),
    statusIdleSolid: Color(0xFF85858B),
    statusConnectedOnSolid: Color(0xFFFFFFFF),
    statusConnectingOnSolid: Color(0xFFFFFFFF),
    statusErrorOnSolid: Color(0xFFFFFFFF),
    statusInfoOnSolid: Color(0xFFFFFFFF),
    statusIdleOnSolid: Color(0xFFFFFFFF),
    statusConnectedWash: Color(0x1A0B7546),
    statusConnectingWash: Color(0x1A8A4B00),
    statusErrorWash: Color(0x1AB42318),
    statusInfoWash: Color(0x1A1F5BD8),
    statusIdleWash: Color(0x1A626268),
  );

  /// `canvas` — application background.
  final Color bgCanvas;

  /// `surface` — cards, grouped lists.
  final Color bgSurface;

  /// `surface-raised` — sheets and dialogs.
  final Color bgRaised;

  /// `surface-2` — what sits inside a card: a pressed row, a field, a menu.
  final Color bgOverlay;

  /// `inset` — recessed surfaces: the log view, a progress track.
  final Color bgInset;

  /// `scrim` — dimmer painted under a modal. Carries its own alpha.
  final Color bgScrim;

  /// `fill` — tracks of the segmented control and the switch, neutral chips,
  /// the search field. Carries its own alpha.
  final Color fill;

  /// `fill-strong` — the sheet handle, a pressed chip. Carries its own alpha.
  final Color fillStrong;

  /// `line` — hairline separators.
  final Color borderSubtle;

  /// `line-default` — the edge of a field, of a flag.
  final Color borderDefault;

  /// `line-strong` — the border of an interactive control: 3:1 and up.
  final Color borderStrong;

  /// `focus` — the keyboard focus ring.
  final Color focusRing;

  /// The thumb of a switch that is off: white in both themes, as on iOS. A
  /// switch that is on draws its thumb in [accentOnSolid] on [accentSolid].
  final Color thumb;

  /// The thumb of the segmented control: white on light, `#636366` on dark.
  final Color segmentThumb;

  /// `ink` — primary text.
  final Color textPrimary;

  /// `ink-2` — secondary text and captions.
  final Color textSecondary;

  /// `ink-3` — metadata and placeholders. Checked against every ground it is
  /// drawn on, not only the surface.
  final Color textTertiary;

  /// Inactive text. Deliberately below the AA threshold (WCAG 1.4.3).
  final Color textDisabled;

  /// Text placed on top of an accent fill.
  final Color textInverse;

  /// `action` — the primary button, a switch that is on. The brand, too: it
  /// is monochrome, chalk on dark and ink on light.
  final Color accentSolid;

  /// `action-pressed` — the primary action under a finger or a pointer.
  final Color accentHover;

  /// `on-action` — content drawn on top of [accentSolid].
  final Color accentOnSolid;

  /// `wash` — a row under a pointer. Carries its own alpha.
  final Color accentWash;

  /// "Connected", and nothing else: words and icons.
  final Color statusConnected;

  /// Transitional state, or something missing: words and icons.
  final Color statusConnecting;

  /// Failure: words and icons.
  final Color statusError;

  /// Information and change: words and icons.
  final Color statusInfo;

  /// At rest: words and icons.
  final Color statusIdle;

  /// [statusConnected] as a line, a dot or a fill — the lit route.
  final Color statusConnectedSolid;

  /// [statusConnecting] as a line, a dot or a fill.
  final Color statusConnectingSolid;

  /// [statusError] as a line, a dot or a fill under white.
  final Color statusErrorSolid;

  /// [statusInfo] as a line, a dot or a fill.
  final Color statusInfoSolid;

  /// [statusIdle] as a line, a dot or a ring — the route at rest.
  final Color statusIdleSolid;

  /// A glyph drawn on [statusConnectedSolid].
  final Color statusConnectedOnSolid;

  /// A glyph drawn on [statusConnectingSolid].
  final Color statusConnectingOnSolid;

  /// A glyph or a word drawn on [statusErrorSolid].
  final Color statusErrorOnSolid;

  /// A glyph drawn on [statusInfoSolid].
  final Color statusInfoOnSolid;

  /// A glyph drawn on [statusIdleSolid].
  final Color statusIdleOnSolid;

  /// Chip background for [statusConnected]. Carries its own alpha.
  final Color statusConnectedWash;

  /// Chip background for [statusConnecting]. Carries its own alpha.
  final Color statusConnectingWash;

  /// Chip background for [statusError]. Carries its own alpha.
  final Color statusErrorWash;

  /// Chip background for [statusInfo]. Carries its own alpha.
  final Color statusInfoWash;

  /// Chip background for [statusIdle]. Carries its own alpha.
  final Color statusIdleWash;

  /// Returns a copy with the given colours replaced.
  @override
  CommyColors copyWith({
    Color? bgCanvas,
    Color? bgSurface,
    Color? bgRaised,
    Color? bgOverlay,
    Color? bgInset,
    Color? bgScrim,
    Color? fill,
    Color? fillStrong,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
    Color? focusRing,
    Color? thumb,
    Color? segmentThumb,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textInverse,
    Color? accentSolid,
    Color? accentHover,
    Color? accentOnSolid,
    Color? accentWash,
    Color? statusConnected,
    Color? statusConnecting,
    Color? statusError,
    Color? statusInfo,
    Color? statusIdle,
    Color? statusConnectedSolid,
    Color? statusConnectingSolid,
    Color? statusErrorSolid,
    Color? statusInfoSolid,
    Color? statusIdleSolid,
    Color? statusConnectedOnSolid,
    Color? statusConnectingOnSolid,
    Color? statusErrorOnSolid,
    Color? statusInfoOnSolid,
    Color? statusIdleOnSolid,
    Color? statusConnectedWash,
    Color? statusConnectingWash,
    Color? statusErrorWash,
    Color? statusInfoWash,
    Color? statusIdleWash,
  }) {
    return CommyColors(
      bgCanvas: bgCanvas ?? this.bgCanvas,
      bgSurface: bgSurface ?? this.bgSurface,
      bgRaised: bgRaised ?? this.bgRaised,
      bgOverlay: bgOverlay ?? this.bgOverlay,
      bgInset: bgInset ?? this.bgInset,
      bgScrim: bgScrim ?? this.bgScrim,
      fill: fill ?? this.fill,
      fillStrong: fillStrong ?? this.fillStrong,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
      focusRing: focusRing ?? this.focusRing,
      thumb: thumb ?? this.thumb,
      segmentThumb: segmentThumb ?? this.segmentThumb,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      textInverse: textInverse ?? this.textInverse,
      accentSolid: accentSolid ?? this.accentSolid,
      accentHover: accentHover ?? this.accentHover,
      accentOnSolid: accentOnSolid ?? this.accentOnSolid,
      accentWash: accentWash ?? this.accentWash,
      statusConnected: statusConnected ?? this.statusConnected,
      statusConnecting: statusConnecting ?? this.statusConnecting,
      statusError: statusError ?? this.statusError,
      statusInfo: statusInfo ?? this.statusInfo,
      statusIdle: statusIdle ?? this.statusIdle,
      statusConnectedSolid: statusConnectedSolid ?? this.statusConnectedSolid,
      statusConnectingSolid:
          statusConnectingSolid ?? this.statusConnectingSolid,
      statusErrorSolid: statusErrorSolid ?? this.statusErrorSolid,
      statusInfoSolid: statusInfoSolid ?? this.statusInfoSolid,
      statusIdleSolid: statusIdleSolid ?? this.statusIdleSolid,
      statusConnectedOnSolid:
          statusConnectedOnSolid ?? this.statusConnectedOnSolid,
      statusConnectingOnSolid:
          statusConnectingOnSolid ?? this.statusConnectingOnSolid,
      statusErrorOnSolid: statusErrorOnSolid ?? this.statusErrorOnSolid,
      statusInfoOnSolid: statusInfoOnSolid ?? this.statusInfoOnSolid,
      statusIdleOnSolid: statusIdleOnSolid ?? this.statusIdleOnSolid,
      statusConnectedWash: statusConnectedWash ?? this.statusConnectedWash,
      statusConnectingWash: statusConnectingWash ?? this.statusConnectingWash,
      statusErrorWash: statusErrorWash ?? this.statusErrorWash,
      statusInfoWash: statusInfoWash ?? this.statusInfoWash,
      statusIdleWash: statusIdleWash ?? this.statusIdleWash,
    );
  }

  /// Interpolates towards [other]. Used when the theme animates.
  @override
  CommyColors lerp(covariant CommyColors? other, double t) {
    if (other == null) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CommyColors(
      bgCanvas: mix(bgCanvas, other.bgCanvas),
      bgSurface: mix(bgSurface, other.bgSurface),
      bgRaised: mix(bgRaised, other.bgRaised),
      bgOverlay: mix(bgOverlay, other.bgOverlay),
      bgInset: mix(bgInset, other.bgInset),
      bgScrim: mix(bgScrim, other.bgScrim),
      fill: mix(fill, other.fill),
      fillStrong: mix(fillStrong, other.fillStrong),
      borderSubtle: mix(borderSubtle, other.borderSubtle),
      borderDefault: mix(borderDefault, other.borderDefault),
      borderStrong: mix(borderStrong, other.borderStrong),
      focusRing: mix(focusRing, other.focusRing),
      thumb: mix(thumb, other.thumb),
      segmentThumb: mix(segmentThumb, other.segmentThumb),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      textTertiary: mix(textTertiary, other.textTertiary),
      textDisabled: mix(textDisabled, other.textDisabled),
      textInverse: mix(textInverse, other.textInverse),
      accentSolid: mix(accentSolid, other.accentSolid),
      accentHover: mix(accentHover, other.accentHover),
      accentOnSolid: mix(accentOnSolid, other.accentOnSolid),
      accentWash: mix(accentWash, other.accentWash),
      statusConnected: mix(statusConnected, other.statusConnected),
      statusConnecting: mix(statusConnecting, other.statusConnecting),
      statusError: mix(statusError, other.statusError),
      statusInfo: mix(statusInfo, other.statusInfo),
      statusIdle: mix(statusIdle, other.statusIdle),
      statusConnectedSolid:
          mix(statusConnectedSolid, other.statusConnectedSolid),
      statusConnectingSolid:
          mix(statusConnectingSolid, other.statusConnectingSolid),
      statusErrorSolid: mix(statusErrorSolid, other.statusErrorSolid),
      statusInfoSolid: mix(statusInfoSolid, other.statusInfoSolid),
      statusIdleSolid: mix(statusIdleSolid, other.statusIdleSolid),
      statusConnectedOnSolid:
          mix(statusConnectedOnSolid, other.statusConnectedOnSolid),
      statusConnectingOnSolid:
          mix(statusConnectingOnSolid, other.statusConnectingOnSolid),
      statusErrorOnSolid: mix(statusErrorOnSolid, other.statusErrorOnSolid),
      statusInfoOnSolid: mix(statusInfoOnSolid, other.statusInfoOnSolid),
      statusIdleOnSolid: mix(statusIdleOnSolid, other.statusIdleOnSolid),
      statusConnectedWash: mix(statusConnectedWash, other.statusConnectedWash),
      statusConnectingWash:
          mix(statusConnectingWash, other.statusConnectingWash),
      statusErrorWash: mix(statusErrorWash, other.statusErrorWash),
      statusInfoWash: mix(statusInfoWash, other.statusInfoWash),
      statusIdleWash: mix(statusIdleWash, other.statusIdleWash),
    );
  }
}
