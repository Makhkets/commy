/// Font family names of the two vendored typefaces.
///
/// Both are embedded in the application rather than taken from the system:
/// identical rendering on five platforms is worth a couple of megabytes, and
/// golden tests are meaningless without it. Licence texts (SIL OFL 1.1) live
/// next to the files in `packages/commy_ui/fonts/` and are shown on the About
/// screen.
abstract final class CommyFonts {
  /// Package that owns the font assets. Needed by `TextStyle.package`.
  static const String package = 'commy_ui';

  /// Interface typeface: Inter.
  static const String ui = 'Inter';

  /// Monospace typeface: JetBrains Mono. Logs, JSON, IP addresses, latency.
  static const String mono = 'JetBrainsMono';

  /// [ui] qualified with its package, as `ThemeData.fontFamily` wants it.
  static const String uiQualified = 'packages/$package/$ui';

  /// [mono] qualified with its package, as `ThemeData.fontFamily` wants it.
  static const String monoQualified = 'packages/$package/$mono';

  /// Regular — 400.
  static const int weightRegular = 400;

  /// Medium — 500.
  static const int weightMedium = 500;

  /// Semi Bold — 600. The heaviest weight we ship.
  static const int weightSemiBold = 600;
}
