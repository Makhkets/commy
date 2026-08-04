import 'dart:ui' as ui;

import 'package:commy_ui/src/tokens/fonts.dart';
import 'package:flutter/material.dart';

/// The type scale, one field per row of the table in
/// docs/04-design-system.md.
///
/// Two conversions happen here and nowhere else:
///
/// * line height is stored in Figma as an absolute pixel value and in Flutter
///   as a multiplier, so every `height` is written as `<leading> / <size>`;
/// * tracking is stored in Figma as a percentage of the size and in Flutter as
///   logical pixels, so every `letterSpacing` is written as
///   `<size> * <percent / 100>`.
///
/// Both are left as visible arithmetic instead of a pre-computed decimal: the
/// numbers stay comparable with the document without a calculator.
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
    required this.numericDisplay,
    required this.numericBody,
    required this.mono,
    required this.monoSmall,
    required this.monoStrong,
  });

  /// Tabular figures. Mandatory on every numeric and monospace style: without
  /// them a speed readout jitters on every digit change, and it shows.
  static const List<ui.FontFeature> tabular = <ui.FontFeature>[
    ui.FontFeature.tabularFigures(),
  ];

  /// The one and only scale.
  static const CommyTypography standard = CommyTypography(
    displayXl: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 44,
      height: 48 / 44,
      fontWeight: FontWeight.w600,
      letterSpacing: 44 * -0.03,
      fontFeatures: tabular,
    ),
    display: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 34,
      height: 40 / 34,
      fontWeight: FontWeight.w600,
      letterSpacing: 34 * -0.025,
      fontFeatures: tabular,
    ),
    title1: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 26,
      height: 32 / 26,
      fontWeight: FontWeight.w600,
      letterSpacing: 26 * -0.02,
    ),
    title2: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      letterSpacing: 20 * -0.015,
    ),
    title3: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 17,
      height: 22 / 17,
      fontWeight: FontWeight.w600,
      letterSpacing: 17 * -0.01,
    ),
    bodyLarge: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 16,
      height: 24 / 16,
      fontWeight: FontWeight.w400,
    ),
    body: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w400,
    ),
    bodyStrong: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 15,
      height: 22 / 15,
      fontWeight: FontWeight.w500,
    ),
    caption: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w400,
    ),
    captionStrong: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 13,
      height: 18 / 13,
      fontWeight: FontWeight.w500,
    ),
    label: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 11 * 0.06,
    ),
    numericDisplay: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 30,
      height: 34 / 30,
      fontWeight: FontWeight.w600,
      letterSpacing: 30 * -0.02,
      fontFeatures: tabular,
    ),
    numericBody: TextStyle(
      fontFamily: CommyFonts.ui,
      package: CommyFonts.package,
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w500,
      fontFeatures: tabular,
    ),
    mono: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w400,
      fontFeatures: tabular,
    ),
    monoSmall: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 11,
      height: 16 / 11,
      fontWeight: FontWeight.w400,
      fontFeatures: tabular,
    ),
    monoStrong: TextStyle(
      fontFamily: CommyFonts.mono,
      package: CommyFonts.package,
      fontSize: 13,
      height: 20 / 13,
      fontWeight: FontWeight.w500,
      fontFeatures: tabular,
    ),
  );

  /// `Display/XL` — 44 / 48, Semi Bold, −3%. Session timer inside the ring.
  final TextStyle displayXl;

  /// `Display` — 34 / 40, Semi Bold, −2.5%. Documentation section heading.
  final TextStyle display;

  /// `Title/1` — 26 / 32, Semi Bold, −2%. Screen heading.
  final TextStyle title1;

  /// `Title/2` — 20 / 26, Semi Bold, −1.5%. Sheet and section heading.
  final TextStyle title2;

  /// `Title/3` — 17 / 22, Semi Bold, −1%. Card heading, node name.
  final TextStyle title3;

  /// `Body/Large` — 16 / 24, Regular. Body text on mobile.
  final TextStyle bodyLarge;

  /// `Body` — 15 / 22, Regular. Body text.
  final TextStyle body;

  /// `Body/Strong` — 15 / 22, Medium. Action label, emphasis in a row.
  final TextStyle bodyStrong;

  /// `Caption` — 13 / 18, Regular. Captions, metadata, tabs.
  final TextStyle caption;

  /// `Caption/Strong` — 13 / 18, Medium. Secondary action.
  final TextStyle captionStrong;

  /// `Label` — 11 / 14, Semi Bold, +6%. Section headers and chips. Always
  /// upper case; the widgets that use it apply the transform.
  final TextStyle label;

  /// `Numeric/Display` — 30 / 34, Semi Bold, −2%. Up and down speed.
  final TextStyle numericDisplay;

  /// `Numeric/Body` — 15 / 20, Medium. Numbers inside rows.
  final TextStyle numericBody;

  /// `Mono` — 13 / 20, JetBrains Mono Regular. Logs, configuration.
  final TextStyle mono;

  /// `Mono/Small` — 11 / 16, JetBrains Mono Regular. Latency, IP, port.
  final TextStyle monoSmall;

  /// `Mono/Strong` — 13 / 20, JetBrains Mono Medium. Routing rule expression.
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
    return CommyTypography(
      displayXl: TextStyle.lerp(displayXl, other.displayXl, t)!,
      display: TextStyle.lerp(display, other.display, t)!,
      title1: TextStyle.lerp(title1, other.title1, t)!,
      title2: TextStyle.lerp(title2, other.title2, t)!,
      title3: TextStyle.lerp(title3, other.title3, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      captionStrong: TextStyle.lerp(captionStrong, other.captionStrong, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      numericDisplay: TextStyle.lerp(numericDisplay, other.numericDisplay, t)!,
      numericBody: TextStyle.lerp(numericBody, other.numericBody, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      monoSmall: TextStyle.lerp(monoSmall, other.monoSmall, t)!,
      monoStrong: TextStyle.lerp(monoStrong, other.monoStrong, t)!,
    );
  }
}
