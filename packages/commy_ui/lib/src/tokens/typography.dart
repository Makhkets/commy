import 'dart:ui' as ui;

import 'package:commy_ui/src/tokens/fonts.dart';
import 'package:flutter/material.dart';

/// The type scale, one field per row of the table in
/// docs/04-design-system.md §3.
///
/// The interface face is Inter 4.1 as one variable font, with two axes:
/// `wght` and `opsz`, the optical size. Flutter maps `fontWeight` onto `wght`
/// on its own; it does **not** pick `opsz` from the font size, so every style
/// below names its optical size explicitly — large text in the tighter,
/// sharper display cut, small text in the open text cut, the way SF Display
/// and SF Text split. A style built outside this scale renders at `opsz 14`,
/// which is one more reason there is no such style.
///
/// Three conversions happen here and nowhere else, each left as visible
/// arithmetic rather than a pre-computed decimal:
///
/// * line height is written as `<leading> / <size>`;
/// * tracking follows Inter's dynamic metrics,
///   `−0.0223 + 0.185·e^(−0.1745·size)` em, written as `<size> * <em>`:
///   large text tighter, small text a hair looser — the size-specific
///   tracking Apple's type is built on;
/// * the optical size is the font size clamped to the axis, 14–32.
///
/// Styles carry no colour. Widgets apply one from `CommyColors` explicitly —
/// there is no implicit "text colour" in this system.
@immutable
class CommyTypography extends ThemeExtension<CommyTypography> {
  /// Creates a type scale. Use [standard] unless a test needs otherwise.
  const CommyTypography({
    required this.displayXl,
    required this.display,
    required this.title1,
    required this.title2,
    required this.title3,
    required this.bodyLarge,
    required this.body,
    required this.bodyStrong,
    required this.caption,
    required this.captionStrong,
    required this.label,
    required this.footnote,
    required this.numericDisplay,
    required this.numericBody,
    required this.mono,
    required this.monoSmall,
    required this.monoStrong,
  });

  /// Tabular figures. Mandatory on every number the user reads — speed,
  /// timer, latency, quota: without them a readout jitters on every digit
  /// change, and it shows.
  static const List<ui.FontFeature> tabular = <ui.FontFeature>[
    ui.FontFeature.tabularFigures(),
  ];

  static const List<ui.FontVariation> _opsz14 = <ui.FontVariation>[
    ui.FontVariation('opsz', 14),
  ];
  static const List<ui.FontVariation> _opsz16 = <ui.FontVariation>[
    ui.FontVariation('opsz', 16),
  ];
  static const List<ui.FontVariation> _opsz20 = <ui.FontVariation>[
    ui.FontVariation('opsz', 20),
  ];
  static const List<ui.FontVariation> _opsz24 = <ui.FontVariation>[
    ui.FontVariation('opsz', 24),
  ];
  static const List<ui.FontVariation> _opsz32 = <ui.FontVariation>[
    ui.FontVariation('opsz', 32),
  ];

  /// The one and only scale.
  static const CommyTypography standard = CommyTypography(
    displayXl: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 44,
      height: 50 / 44,
      fontWeight: FontWeight.w700,
      letterSpacing: 44 * -0.0222,
      fontVariations: _opsz32,
      fontFeatures: tabular,
    ),
    display: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 32,
      height: 38 / 32,
      fontWeight: FontWeight.w700,
      letterSpacing: 32 * -0.0216,
      fontVariations: _opsz32,
    ),
    title1: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 24,
      height: 30 / 24,
      fontWeight: FontWeight.w700,
      letterSpacing: 24 * -0.0195,
      fontVariations: _opsz24,
    ),
    title2: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 20 * -0.0167,
      fontVariations: _opsz20,
    ),
    title3: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 16 * -0.011,
      fontVariations: _opsz16,
    ),
    bodyLarge: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 16 * -0.011,
      fontVariations: _opsz16,
    ),
    body: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.w400,
      letterSpacing: 16 * -0.011,
      fontVariations: _opsz16,
    ),
    bodyStrong: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.w600,
      letterSpacing: 16 * -0.011,
      fontVariations: _opsz16,
    ),
    caption: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 14 * -0.0062,
      fontVariations: _opsz14,
    ),
    captionStrong: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 14 * -0.0062,
      fontVariations: _opsz14,
    ),
    label: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 12 * 0.0005,
      fontVariations: _opsz14,
    ),
    footnote: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      letterSpacing: 12 * 0.0005,
      fontVariations: _opsz14,
    ),
    numericDisplay: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 32,
      height: 38 / 32,
      fontWeight: FontWeight.w600,
      letterSpacing: 32 * -0.0216,
      fontVariations: _opsz32,
      fontFeatures: tabular,
    ),
    numericBody: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      letterSpacing: 14 * -0.0062,
      fontVariations: _opsz14,
      fontFeatures: tabular,
    ),
    mono: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 12,
      height: 18 / 12,
      fontWeight: FontWeight.w400,
      fontFeatures: tabular,
    ),
    monoSmall: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 12,
      height: 16 / 12,
      fontWeight: FontWeight.w400,
      fontFeatures: tabular,
    ),
    monoStrong: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 12,
      height: 18 / 12,
      fontWeight: FontWeight.w500,
      fontFeatures: tabular,
    ),
  );

  /// 44 / 50, Bold, display cut. Reserved for one large number.
  final TextStyle displayXl;

  /// 32 / 38, Bold, display cut. The answer at the top of the main screen.
  final TextStyle display;

  /// 24 / 30, Bold. A screen's title.
  final TextStyle title1;

  /// 20 / 26, Semi Bold. A sheet's or a card's title.
  final TextStyle title2;

  /// 16 / 22, Semi Bold. A server's name, a row's title.
  final TextStyle title3;

  /// 16 / 24, Regular. Paragraphs of explanation.
  final TextStyle bodyLarge;

  /// 16 / 22, Regular. The text of a row.
  final TextStyle body;

  /// 16 / 22, Semi Bold. A button's label, emphasis.
  final TextStyle bodyStrong;

  /// 14 / 20, Regular. A row's subtitle, captions.
  final TextStyle caption;

  /// 14 / 20, Semi Bold. A list section's header, a small button.
  final TextStyle captionStrong;

  /// 12 / 16, Semi Bold. Badges, chips, protocol tags. Sentence case: the
  /// widgets that use it no longer upper-case it.
  final TextStyle label;

  /// 12 / 16, Regular. A footnote under a group, metadata.
  final TextStyle footnote;

  /// 32 / 38, Semi Bold, tabular. A large figure.
  final TextStyle numericDisplay;

  /// 14 / 20, Medium, tabular. Latency, speed, quota inside rows.
  final TextStyle numericBody;

  /// 12 / 18, JetBrains Mono Regular. Logs and configuration — code only.
  final TextStyle mono;

  /// 12 / 16, JetBrains Mono Regular. Dense log lines.
  final TextStyle monoSmall;

  /// 12 / 18, JetBrains Mono Medium. A routing rule's expression.
  final TextStyle monoStrong;

  /// Returns a copy with the given styles replaced.
  @override
  CommyTypography copyWith({
    TextStyle? displayXl,
    TextStyle? display,
    TextStyle? title1,
    TextStyle? title2,
    TextStyle? title3,
    TextStyle? bodyLarge,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? label,
    TextStyle? footnote,
    TextStyle? numericDisplay,
    TextStyle? numericBody,
    TextStyle? mono,
    TextStyle? monoSmall,
    TextStyle? monoStrong,
  }) {
    return CommyTypography(
      displayXl: displayXl ?? this.displayXl,
      display: display ?? this.display,
      title1: title1 ?? this.title1,
      title2: title2 ?? this.title2,
      title3: title3 ?? this.title3,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      caption: caption ?? this.caption,
      captionStrong: captionStrong ?? this.captionStrong,
      label: label ?? this.label,
      footnote: footnote ?? this.footnote,
      numericDisplay: numericDisplay ?? this.numericDisplay,
      numericBody: numericBody ?? this.numericBody,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
      monoStrong: monoStrong ?? this.monoStrong,
    );
  }

  /// Interpolates towards [other].
  @override
  CommyTypography lerp(covariant CommyTypography? other, double t) {
    if (other == null) {
      return this;
    }
    TextStyle mix(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return CommyTypography(
      displayXl: mix(displayXl, other.displayXl),
      display: mix(display, other.display),
      title1: mix(title1, other.title1),
      title2: mix(title2, other.title2),
      title3: mix(title3, other.title3),
      bodyLarge: mix(bodyLarge, other.bodyLarge),
      body: mix(body, other.body),
      bodyStrong: mix(bodyStrong, other.bodyStrong),
      caption: mix(caption, other.caption),
      captionStrong: mix(captionStrong, other.captionStrong),
      label: mix(label, other.label),
      footnote: mix(footnote, other.footnote),
      numericDisplay: mix(numericDisplay, other.numericDisplay),
      numericBody: mix(numericBody, other.numericBody),
      mono: mix(mono, other.mono),
      monoSmall: mix(monoSmall, other.monoSmall),
      monoStrong: mix(monoStrong, other.monoStrong),
    );
  }
}
