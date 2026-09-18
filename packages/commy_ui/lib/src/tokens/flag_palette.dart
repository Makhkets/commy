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

  /// Czechia blue, the hoist triangle.
  static const Color czBlue = Color(0xFF11457E);

  /// Czechia red.
  static const Color czRed = Color(0xFFD7141A);

  /// Ukraine blue.
  static const Color uaBlue = Color(0xFF0057B7);

  /// Ukraine yellow.
  static const Color uaYellow = Color(0xFFFFD700);

  /// Kazakhstan sky blue.
  static const Color kzBlue = Color(0xFF00AFCA);

  /// Kazakhstan gold.
  static const Color kzGold = Color(0xFFFEC50C);

  /// Estonia blue.
  static const Color eeBlue = Color(0xFF0072CE);

  /// Hungary red.
  static const Color huRed = Color(0xFFCE2939);

  /// Hungary green.
  static const Color huGreen = Color(0xFF477050);

  /// Bulgaria green.
  static const Color bgGreen = Color(0xFF00966E);

  /// Bulgaria red.
  static const Color bgRed = Color(0xFFD62612);

  /// Romania blue, shared with Moldova.
  static const Color roBlue = Color(0xFF002B7F);

  /// Romania yellow, shared with Moldova.
  static const Color roYellow = Color(0xFFFCD116);

  /// Romania red, shared with Moldova.
  static const Color roRed = Color(0xFFCE1126);

  /// Moldova's coat of arms, reduced to the colour it reads as at 26 × 20.
  static const Color mdEmblem = Color(0xFF8A5A2B);

  /// Luxembourg light blue.
  static const Color luBlue = Color(0xFF00A1DE);

  /// Armenia red.
  static const Color amRed = Color(0xFFD90012);

  /// Armenia blue.
  static const Color amBlue = Color(0xFF0033A0);

  /// Armenia orange.
  static const Color amOrange = Color(0xFFF2A800);

  /// Belgium yellow.
  static const Color beYellow = Color(0xFFFAE042);

  /// Belgium red.
  static const Color beRed = Color(0xFFED2939);

  /// Ireland green.
  static const Color ieGreen = Color(0xFF169B62);

  /// Ireland orange.
  static const Color ieOrange = Color(0xFFFF883E);

  /// Denmark red.
  static const Color dkRed = Color(0xFFC8102E);

  /// Iceland blue.
  static const Color isBlue = Color(0xFF02529C);

  /// Iceland red.
  static const Color isRed = Color(0xFFDC1E35);

  /// Portugal green.
  static const Color ptGreen = Color(0xFF006600);

  /// Portugal red.
  static const Color ptRed = Color(0xFFFF0000);

  /// Portugal's armillary sphere, as the yellow it reads as.
  static const Color ptYellow = Color(0xFFFFE900);

  /// Greece blue.
  static const Color grBlue = Color(0xFF0D5EAF);

  /// Serbia red, shared with Croatia, Slovakia and Slovenia: four flags that
  /// differ by their shields, not by their cloth.
  static const Color slavicRed = Color(0xFFC6363C);

  /// Serbia blue, shared like [slavicRed].
  static const Color slavicBlue = Color(0xFF0C4076);

  /// Georgia red.
  static const Color geRed = Color(0xFFFF0000);

  /// Azerbaijan blue.
  static const Color azBlue = Color(0xFF00B5E2);

  /// Azerbaijan red.
  static const Color azRed = Color(0xFFEF3340);

  /// Azerbaijan green.
  static const Color azGreen = Color(0xFF509E2F);

  /// Belarus red.
  static const Color byRed = Color(0xFFCF101A);

  /// Belarus green.
  static const Color byGreen = Color(0xFF007C30);

  /// Cyprus copper, the island.
  static const Color cyCopper = Color(0xFFD57800);

  /// Cyprus olive green, the branches.
  static const Color cyGreen = Color(0xFF4E5B31);

  /// Malta red.
  static const Color mtRed = Color(0xFFCF142B);

  /// Malta's George Cross, as the grey it reads as.
  static const Color mtGrey = Color(0xFF9B9B9B);

  /// Bosnia and Herzegovina blue.
  static const Color baBlue = Color(0xFF002395);

  /// Bosnia and Herzegovina yellow.
  static const Color baYellow = Color(0xFFFECB00);

  /// United Arab Emirates red.
  static const Color aeRed = Color(0xFFFF0000);

  /// United Arab Emirates green.
  static const Color aeGreen = Color(0xFF00732F);

  /// Israel blue.
  static const Color ilBlue = Color(0xFF0038B8);

  /// India saffron.
  static const Color inSaffron = Color(0xFFFF9933);

  /// India green.
  static const Color inGreen = Color(0xFF138808);

  /// India navy, the wheel.
  static const Color inNavy = Color(0xFF000080);

  /// South Korea red.
  static const Color krRed = Color(0xFFCD2E3A);

  /// South Korea blue.
  static const Color krBlue = Color(0xFF0047A0);

  /// Singapore red, shared with Indonesia and Luxembourg.
  static const Color sgRed = Color(0xFFEF3340);

  /// Hong Kong red.
  static const Color hkRed = Color(0xFFDE2910);

  /// China red, shared with Vietnam.
  static const Color cnRed = Color(0xFFDE2910);

  /// China yellow, shared with Vietnam.
  static const Color cnYellow = Color(0xFFFFDE00);

  /// Taiwan red.
  static const Color twRed = Color(0xFFFE0000);

  /// Taiwan blue.
  static const Color twBlue = Color(0xFF000095);

  /// Thailand red.
  static const Color thRed = Color(0xFFA51931);

  /// Thailand blue.
  static const Color thBlue = Color(0xFF2D2A4A);

  /// Canada red.
  static const Color caRed = Color(0xFFD80621);

  /// Australia blue, shared with New Zealand.
  static const Color auBlue = Color(0xFF00008B);

  /// New Zealand red, the stars.
  static const Color nzRed = Color(0xFFCC142B);

  /// Brazil green.
  static const Color brGreen = Color(0xFF009C3B);

  /// Brazil yellow.
  static const Color brYellow = Color(0xFFFFDF00);

  /// Brazil blue.
  static const Color brBlue = Color(0xFF002776);

  /// Mexico green.
  static const Color mxGreen = Color(0xFF006847);

  /// Mexico red.
  static const Color mxRed = Color(0xFFCE1126);

  /// Mexico's coat of arms, as the brown it reads as.
  static const Color mxEmblem = Color(0xFF8C6A3B);

  /// Argentina light blue.
  static const Color arBlue = Color(0xFF74ACDF);

  /// Argentina's Sun of May.
  static const Color arSun = Color(0xFFF6B40E);

  /// Chile blue.
  static const Color clBlue = Color(0xFF0039A6);

  /// Chile red.
  static const Color clRed = Color(0xFFD52B1E);

  /// South Africa red.
  static const Color zaRed = Color(0xFFE03C31);

  /// South Africa blue.
  static const Color zaBlue = Color(0xFF001489);

  /// South Africa green.
  static const Color zaGreen = Color(0xFF007749);

  /// South Africa gold.
  static const Color zaGold = Color(0xFFFFB81C);

  /// Nigeria green.
  static const Color ngGreen = Color(0xFF008751);
}
