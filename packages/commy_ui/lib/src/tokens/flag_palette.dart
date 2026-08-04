import 'package:flutter/material.dart';

/// The colours of the vector country flags.
///
/// Flags are drawn by us, from bands and shapes, because emoji flags depend on
/// a system font, break line height, and on Windows render as two letters —
/// which is exactly what we are getting away from.
///
/// These are national colours, not design tokens: they do not change with the
/// theme and they are not up for discussion. They live in `tokens/` only
/// because that is where rule R4 allows colour literals to exist.
abstract final class CommyFlagPalette {
  /// Plain white, used by most European flags.
  static const Color white = Color(0xFFFFFFFF);

  /// Plain black, used by the German flag.
  static const Color black = Color(0xFF000000);

  /// Netherlands red.
  static const Color nlRed = Color(0xFFAE1C28);

  /// Netherlands blue.
  static const Color nlBlue = Color(0xFF21468B);

  /// Germany red.
  static const Color deRed = Color(0xFFDD0000);

  /// Germany gold.
  static const Color deGold = Color(0xFFFFCE00);

  /// France blue.
  static const Color frBlue = Color(0xFF002395);

  /// France red.
  static const Color frRed = Color(0xFFED2939);

  /// Poland crimson.
  static const Color plRed = Color(0xFFDC143C);

  /// Lithuania yellow.
  static const Color ltYellow = Color(0xFFFDB913);

  /// Lithuania green.
  static const Color ltGreen = Color(0xFF006A44);

  /// Lithuania red.
  static const Color ltRed = Color(0xFFC1272D);

  /// Russia blue.
  static const Color ruBlue = Color(0xFF0039A6);

  /// Russia red.
  static const Color ruRed = Color(0xFFD52B1E);

  /// Latvia carmine.
  static const Color lvCarmine = Color(0xFF9E3039);

  /// Finland blue.
  static const Color fiBlue = Color(0xFF003580);

  /// Japan red disc.
  static const Color jpRed = Color(0xFFBC002D);

  /// European Union blue.
  static const Color euBlue = Color(0xFF003399);

  /// European Union gold.
  static const Color euGold = Color(0xFFFFCC00);

  /// United States red.
  static const Color usRed = Color(0xFFB22234);

  /// United States canton blue.
  static const Color usBlue = Color(0xFF3C3B6E);

  /// United Kingdom blue.
  static const Color gbBlue = Color(0xFF012169);

  /// United Kingdom red.
  static const Color gbRed = Color(0xFFC8102E);

  /// Sweden blue.
  static const Color seBlue = Color(0xFF006AA7);

  /// Sweden yellow.
  static const Color seYellow = Color(0xFFFECC00);

  /// Norway red.
  static const Color noRed = Color(0xFFBA0C2F);

  /// Norway blue.
  static const Color noBlue = Color(0xFF00205B);

  /// Switzerland red.
  static const Color chRed = Color(0xFFDA291C);

  /// Turkey red.
  static const Color trRed = Color(0xFFE30A17);

  /// Austria red.
  static const Color atRed = Color(0xFFED2939);

  /// Spain crimson.
  static const Color esRed = Color(0xFFAA151B);

  /// Spain yellow.
  static const Color esYellow = Color(0xFFF1BF00);

  /// Italy green.
  static const Color itGreen = Color(0xFF008C45);

  /// Italy red.
  static const Color itRed = Color(0xFFCD212A);
}
