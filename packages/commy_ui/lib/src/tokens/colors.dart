import 'package:flutter/material.dart';

/// Semantic colour tokens of the "Graphite and signal" system.
///
/// This class is the whole colour vocabulary of the product: the raw Ink /
/// Jade / Amber / Rose / Azure ramps of docs/04-design-system.md never reach
/// widget code, only the semantic names below do. Rule R4 — nothing outside
/// `lib/src/tokens/` may write a colour literal.
///
/// Names are the camelCase form of the Figma variable: `bg/surface` becomes
/// [bgSurface], `status/connected` becomes [statusConnected]. A name that
/// disagrees with Figma is a bug, not a detail.
///
/// Alpha-bearing tokens are pre-multiplied here instead of being produced with
/// `withOpacity` at the call site: the value has to be identical in every
/// theme, and a const `Color` is the only way to guarantee that.
@immutable
class CommyColors extends ThemeExtension<CommyColors> {
  /// Creates a colour set. Use [dark] or [light]; build a new one only in
  /// tests or when previewing an alternative signature hue.
  const CommyColors({
    required this.bgCanvas,
    required this.bgSurface,
    required this.bgGroupHeader,
    required this.bgRaised,
    required this.bgOverlay,
    required this.bgInset,
    required this.bgScrim,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
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
    required this.statusConnectedWash,
    required this.statusConnectingWash,
    required this.statusErrorWash,
    required this.statusInfoWash,
    required this.statusIdleWash,
    required this.statusConnectedGlow,
    required this.statusErrorGlow,
  });

  /// Fully transparent. Exists so that no widget has to reach for
  /// `Colors.transparent`, which rule R4 forbids outside this directory.
  static const Color transparent = Color(0x00000000);

  /// The dark theme. This is the theme the product was designed in.
  static const CommyColors dark = CommyColors(
    bgCanvas: Color(0xFF0A0B0D),
    bgSurface: Color(0xFF131519),
    bgGroupHeader: Color(0xFF1B1D21),
    bgRaised: Color(0xFF1B1D21),
    bgOverlay: Color(0xFF24272C),
    bgInset: Color(0xFF0E1013),
    bgScrim: Color(0xA3000000),
    borderSubtle: Color(0xFF1B1D21),
    borderDefault: Color(0xFF24272C),
    borderStrong: Color(0xFF6C7178),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFFB3B7BD),
    textTertiary: Color(0xFF8D9299),
    textDisabled: Color(0xFF6C7178),
    textInverse: Color(0xFF0A0B0D),
    accentSolid: Color(0xFFF2F3F5),
    accentHover: Color(0xFFFFFFFF),
    accentOnSolid: Color(0xFF0A0B0D),
    accentWash: Color(0x14F2F3F5),
    statusConnected: Color(0xFF2FD98A),
    statusConnecting: Color(0xFFF0A93B),
    statusError: Color(0xFFF76C6C),
    statusInfo: Color(0xFF63A8FF),
    statusIdle: Color(0xFF8D9299),
    statusConnectedWash: Color(0x242FD98A),
    statusConnectingWash: Color(0x24F0A93B),
    statusErrorWash: Color(0x24F76C6C),
    statusInfoWash: Color(0x2463A8FF),
    statusIdleWash: Color(0x248D9299),
    statusConnectedGlow: Color(0x3D2FD98A),
    statusErrorGlow: Color(0x3DF76C6C),
  );

  /// The light theme. Derived from the dark one, never "left to happen".
  static const CommyColors light = CommyColors(
    bgCanvas: Color(0xFFF6F7F9),
    bgSurface: Color(0xFFFFFFFF),
    bgGroupHeader: Color(0xFFF2F3F5),
    bgRaised: Color(0xFFFFFFFF),
    bgOverlay: Color(0xFFF2F3F5),
    bgInset: Color(0xFFFAFBFC),
    bgScrim: Color(0x66131519),
    borderSubtle: Color(0xFFE6E8EB),
    borderDefault: Color(0xFFD2D6DB),
    borderStrong: Color(0xFF8D9299),
    textPrimary: Color(0xFF131519),
    textSecondary: Color(0xFF4E535B),
    textTertiary: Color(0xFF6C7178),
    textDisabled: Color(0xFFB3B7BD),
    textInverse: Color(0xFFFFFFFF),
    accentSolid: Color(0xFF131519),
    accentHover: Color(0xFF24272C),
    accentOnSolid: Color(0xFFFFFFFF),
    accentWash: Color(0x0F131519),
    statusConnected: Color(0xFF0C7A4A),
    statusConnecting: Color(0xFF93560A),
    statusError: Color(0xFFA02020),
    statusInfo: Color(0xFF1D4FD8),
    statusIdle: Color(0xFF6C7178),
    statusConnectedWash: Color(0x1A0C7A4A),
    statusConnectingWash: Color(0x1A93560A),
    statusErrorWash: Color(0x1AA02020),
    statusInfoWash: Color(0x1A1D4FD8),
    statusIdleWash: Color(0x1A6C7178),
    statusConnectedGlow: Color(0x2E0C7A4A),
    statusErrorGlow: Color(0x2EA02020),
  );

  /// Application background. Elevation level 0.
  final Color bgCanvas;

  /// Cards and list rows. Elevation level 1.
  final Color bgSurface;

  /// Group header: a subscription sitting above its own nodes.
  final Color bgGroupHeader;

  /// Sheets, dialogs, menus and the connect disc. Elevation level 2.
  final Color bgRaised;

  /// Hover, row selection, input field background.
  final Color bgOverlay;

  /// Recessed surfaces: the log view, a progress track.
  final Color bgInset;

  /// Dimmer painted under a modal. Carries its own alpha.
  final Color bgScrim;

  /// Separators inside one card.
  final Color borderSubtle;

  /// Borders of cards and fields.
  final Color borderDefault;

  /// Focus ring and active border.
  final Color borderStrong;

  /// Primary text.
  final Color textPrimary;

  /// Captions and metadata.
  final Color textSecondary;

  /// Third level. Never used below 13 px — see the contrast table.
  final Color textTertiary;

  /// Inactive text. Deliberately below the AA threshold (WCAG 1.4.3).
  final Color textDisabled;

  /// Text placed on top of an accent fill.
  final Color textInverse;

  /// Brand colour and primary action. Chalk on dark, ink on light.
  final Color accentSolid;

  /// Hover state of the primary action.
  final Color accentHover;

  /// Content drawn on top of [accentSolid].
  final Color accentOnSolid;

  /// Backing wash of a selected row. Carries its own alpha.
  final Color accentWash;

  /// "Connected", and nothing else. The signature hue of the product.
  final Color statusConnected;

  /// Transitional state: starting or stopping.
  final Color statusConnecting;

  /// Failure, disconnection.
  final Color statusError;

  /// Informational.
  final Color statusInfo;

  /// Disconnected.
  final Color statusIdle;

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

  /// Glow of the connect ring when connected. The only glow in the product.
  final Color statusConnectedGlow;

  /// Glow of the connect ring when errored.
  ///
  /// The semantic table of docs/04-design-system.md spells out only
  /// `status/connected/glow`; the Figma effect `Glow/Ошибка` exists too, so
  /// this token repeats the same alpha rule (24% dark, 18% light) on
  /// [statusError].
  final Color statusErrorGlow;

  /// Returns a copy with the given colours replaced.
  @override
  CommyColors copyWith({
    Color? bgCanvas,
    Color? bgSurface,
    Color? bgGroupHeader,
    Color? bgRaised,
    Color? bgOverlay,
    Color? bgInset,
    Color? bgScrim,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
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
    Color? statusConnectedWash,
    Color? statusConnectingWash,
    Color? statusErrorWash,
    Color? statusInfoWash,
    Color? statusIdleWash,
    Color? statusConnectedGlow,
    Color? statusErrorGlow,
  }) {
    return CommyColors(
      bgCanvas: bgCanvas ?? this.bgCanvas,
      bgSurface: bgSurface ?? this.bgSurface,
      bgGroupHeader: bgGroupHeader ?? this.bgGroupHeader,
      bgRaised: bgRaised ?? this.bgRaised,
      bgOverlay: bgOverlay ?? this.bgOverlay,
      bgInset: bgInset ?? this.bgInset,
      bgScrim: bgScrim ?? this.bgScrim,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
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
      statusConnectedWash: statusConnectedWash ?? this.statusConnectedWash,
      statusConnectingWash: statusConnectingWash ?? this.statusConnectingWash,
      statusErrorWash: statusErrorWash ?? this.statusErrorWash,
      statusInfoWash: statusInfoWash ?? this.statusInfoWash,
      statusIdleWash: statusIdleWash ?? this.statusIdleWash,
      statusConnectedGlow: statusConnectedGlow ?? this.statusConnectedGlow,
      statusErrorGlow: statusErrorGlow ?? this.statusErrorGlow,
    );
  }

  /// Interpolates towards [other]. Used when the theme animates.
  @override
  CommyColors lerp(covariant CommyColors? other, double t) {
    if (other == null) {
      return this;
    }
    return CommyColors(
      bgCanvas: Color.lerp(bgCanvas, other.bgCanvas, t)!,
      bgSurface: Color.lerp(bgSurface, other.bgSurface, t)!,
      bgGroupHeader: Color.lerp(bgGroupHeader, other.bgGroupHeader, t)!,
      bgRaised: Color.lerp(bgRaised, other.bgRaised, t)!,
      bgOverlay: Color.lerp(bgOverlay, other.bgOverlay, t)!,
      bgInset: Color.lerp(bgInset, other.bgInset, t)!,
      bgScrim: Color.lerp(bgScrim, other.bgScrim, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      accentSolid: Color.lerp(accentSolid, other.accentSolid, t)!,
      accentHover: Color.lerp(accentHover, other.accentHover, t)!,
      accentOnSolid: Color.lerp(accentOnSolid, other.accentOnSolid, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      statusConnected: Color.lerp(statusConnected, other.statusConnected, t)!,
      statusConnecting: Color.lerp(
        statusConnecting,
        other.statusConnecting,
        t,
      )!,
      statusError: Color.lerp(statusError, other.statusError, t)!,
      statusInfo: Color.lerp(statusInfo, other.statusInfo, t)!,
      statusIdle: Color.lerp(statusIdle, other.statusIdle, t)!,
      statusConnectedWash: Color.lerp(
        statusConnectedWash,
        other.statusConnectedWash,
        t,
      )!,
      statusConnectingWash: Color.lerp(
        statusConnectingWash,
        other.statusConnectingWash,
        t,
      )!,
      statusErrorWash: Color.lerp(statusErrorWash, other.statusErrorWash, t)!,
      statusInfoWash: Color.lerp(statusInfoWash, other.statusInfoWash, t)!,
      statusIdleWash: Color.lerp(statusIdleWash, other.statusIdleWash, t)!,
      statusConnectedGlow: Color.lerp(
        statusConnectedGlow,
        other.statusConnectedGlow,
        t,
      )!,
      statusErrorGlow: Color.lerp(statusErrorGlow, other.statusErrorGlow, t)!,
    );
  }
}
