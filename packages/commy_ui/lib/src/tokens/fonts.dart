/// Font family names of the two vendored typefaces.
///
/// Both are embedded in the application rather than taken from the system:
/// identical rendering on five platforms is worth the bytes, and golden tests
/// are meaningless without it. Inter ships as one variable font with a weight
/// and an optical-size axis (docs/04-design-system.md §3). Licence texts (SIL
/// OFL 1.1) live next to the files in `packages/commy_ui/fonts/` and are
/// shown on the About screen.
abstract final class CommyFonts {
  /// Package that owns the font assets. Needed by `TextStyle.package`.
  static const String package = 'commy_ui';

  /// Interface typeface: Inter, variable (`wght` 100–900, `opsz` 14–32).
  static const String ui = 'Inter';

  /// Monospace typeface: JetBrains Mono. Code only — logs, JSON, a routing
  /// rule's expression. Numbers in the interface are Inter, tabular.
  static const String mono = 'JetBrainsMono';

  /// [ui] qualified with its package, as `ThemeData.fontFamily` wants it.
  static const String uiQualified = 'packages/$package/$ui';

  /// [mono] qualified with its package, as `ThemeData.fontFamily` wants it.
  static const String monoQualified = 'packages/$package/$mono';

  /// Regular — 400.
  static const int weightRegular = 400;

  /// Medium — 500.
  static const int weightMedium = 500;

  /// Semi Bold — 600.
  static const int weightSemiBold = 600;

  /// Bold — 700. Titles from 24 up only.
  static const int weightBold = 700;
}
