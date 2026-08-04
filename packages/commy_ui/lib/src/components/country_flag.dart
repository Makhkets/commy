import 'dart:math' as math;

import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/flag_palette.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A country flag, drawn from bands and shapes rather than typed as an emoji.
///
/// Emoji flags are banned in this product and the reason is not taste. They
/// come from whatever the system font happens to be, so the same list looks
/// different on two phones; they carry their own line height and shove every
/// row they sit in around; and on Windows they render as the two-letter
/// country code, which is precisely the failure mode a flag exists to avoid.
///
/// The flag is [CommySizes.flagWidth] × [CommySizes.flagHeight] — 26 × 20 —
/// with `radius/flag` corners and a hairline of `border/default`. The edge
/// matters: without it a white flag on a light surface has no shape at all.
///
/// An unrecognised or missing code is **not** an error state. It draws the
/// neutral chip — the same 26 × 20 silhouette with a globe mark — because a
/// node whose country we could not guess is an ordinary node, and a red cross
/// next to its name would be a lie about its health.
///
/// The numbers inside the painters below are flag geometry: the ratios that
/// define what a Dutch tricolour *is*. They are not design tokens and there is
/// nothing to theme about them, which is why they sit here rather than in
/// `tokens/`. The colours, which could otherwise tempt someone into writing a
/// literal, all come from [CommyFlagPalette].
class CountryFlag extends StatelessWidget {
  /// Creates a flag for [countryCode].
  ///
  /// [countryCode] is an ISO 3166-1 alpha-2 code, as `ProxyNode.countryCode`
  /// carries it — case and surrounding blanks do not matter. `EU` is accepted
  /// as well, for the auto-select group panels usually ship. `null` and
  /// anything unknown draw the neutral chip.
  const CountryFlag({
    this.countryCode,
    this.semanticLabel,
    super.key,
  });

  /// ISO 3166-1 alpha-2 code, or `null` when the country is unknown.
  final String? countryCode;

  /// Name of the country, announced to assistive technology.
  ///
  /// Left `null` in a row that already says where the node is — the flag is
  /// then decoration and is hidden from the screen reader rather than read
  /// out as a second, redundant fact.
  final String? semanticLabel;

  /// Whether a flag is drawn for [code], as opposed to the neutral chip.
  ///
  /// Screens use it to decide whether a flag is worth the horizontal space at
  /// all; nothing breaks when it returns false.
  static bool isSupported(String? code) => _designOf(code) != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final flag = SizedBox(
      width: CommySizes.flagWidth,
      height: CommySizes.flagHeight,
      child: CustomPaint(
        painter: _FlagPainter(
          design: _designOf(countryCode),
          radius: context.radii.flag,
          edge: colors.borderDefault,
          neutralFill: colors.bgOverlay,
          neutralMark: colors.textTertiary,
        ),
      ),
    );

    final label = semanticLabel;
    if (label == null) {
      return ExcludeSemantics(child: flag);
    }
    return Semantics(label: label, image: true, child: flag);
  }

  static _FlagDesign? _designOf(String? code) {
    if (code == null) {
      return null;
    }
    return switch (code.trim().toUpperCase()) {
      'NL' => _FlagDesign.nl,
      'DE' => _FlagDesign.de,
      'FR' => _FlagDesign.fr,
      'PL' => _FlagDesign.pl,
      'LT' => _FlagDesign.lt,
      'RU' => _FlagDesign.ru,
      'LV' => _FlagDesign.lv,
      'FI' => _FlagDesign.fi,
      'JP' => _FlagDesign.jp,
      'EU' => _FlagDesign.eu,
      'US' => _FlagDesign.us,
      // Panels write both; `UK` is not an ISO code but it is what people type.
      'GB' || 'UK' => _FlagDesign.gb,
      'SE' => _FlagDesign.se,
      'NO' => _FlagDesign.no,
      'CH' => _FlagDesign.ch,
      'TR' => _FlagDesign.tr,
      'AT' => _FlagDesign.at,
      'ES' => _FlagDesign.es,
      'IT' => _FlagDesign.it,
      _ => null,
    };
  }
}

/// The flags this package knows how to draw.
enum _FlagDesign {
  nl,
  de,
  fr,
  pl,
  lt,
  ru,
  lv,
  fi,
  jp,
  eu,
  us,
  gb,
  se,
  no,
  ch,
  tr,
  at,
  es,
  it,
}

class _FlagPainter extends CustomPainter {
  const _FlagPainter({
    required this.design,
    required this.radius,
    required this.edge,
    required this.neutralFill,
    required this.neutralMark,
  });

  /// Which flag to draw, or `null` for the neutral chip.
  final _FlagDesign? design;

  /// Corner radius, `radius/flag`.
  final double radius;

  /// Hairline around the flag, `border/default`.
  final Color edge;

  /// Field of the neutral chip, `bg/overlay`.
  final Color neutralFill;

  /// Globe mark of the neutral chip, `text/tertiary`.
  final Color neutralMark;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    canvas
      ..save()
      ..clipRRect(shape);
    final flag = design;
    if (flag == null) {
      _paintNeutral(canvas, size);
    } else {
      _paintField(canvas, size, flag);
    }
    canvas
      ..restore()
      ..drawRRect(
        shape.deflate(CommySizes.borderThin / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = CommySizes.borderThin
          ..color = edge,
      );
  }

  void _paintField(Canvas canvas, Size size, _FlagDesign flag) {
    switch (flag) {
      case _FlagDesign.nl:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.nlRed,
          CommyFlagPalette.white,
          CommyFlagPalette.nlBlue,
        ]);
      case _FlagDesign.de:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.black,
          CommyFlagPalette.deRed,
          CommyFlagPalette.deGold,
        ]);
      case _FlagDesign.fr:
        _vertical(canvas, size, const <Color>[
          CommyFlagPalette.frBlue,
          CommyFlagPalette.white,
          CommyFlagPalette.frRed,
        ]);
      case _FlagDesign.pl:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.white,
          CommyFlagPalette.plRed,
        ]);
      case _FlagDesign.lt:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.ltYellow,
          CommyFlagPalette.ltGreen,
          CommyFlagPalette.ltRed,
        ]);
      case _FlagDesign.ru:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.white,
          CommyFlagPalette.ruBlue,
          CommyFlagPalette.ruRed,
        ]);
      case _FlagDesign.lv:
        // Carmine, white, carmine at 2 : 1 : 2 — the white stripe is half the
        // width of the ones around it, and that is the whole flag.
        _horizontal(
          canvas,
          size,
          const <Color>[
            CommyFlagPalette.lvCarmine,
            CommyFlagPalette.white,
            CommyFlagPalette.lvCarmine,
          ],
          const <double>[2, 1, 2],
        );
      case _FlagDesign.at:
        _horizontal(canvas, size, const <Color>[
          CommyFlagPalette.atRed,
          CommyFlagPalette.white,
          CommyFlagPalette.atRed,
        ]);
      case _FlagDesign.es:
        _horizontal(
          canvas,
          size,
          const <Color>[
            CommyFlagPalette.esRed,
            CommyFlagPalette.esYellow,
            CommyFlagPalette.esRed,
          ],
          const <double>[1, 2, 1],
        );
      case _FlagDesign.it:
        _vertical(canvas, size, const <Color>[
          CommyFlagPalette.itGreen,
          CommyFlagPalette.white,
          CommyFlagPalette.itRed,
        ]);
      case _FlagDesign.fi:
        _fill(canvas, size, CommyFlagPalette.white);
        _nordicCross(canvas, size, CommyFlagPalette.fiBlue, _crossThick);
      case _FlagDesign.se:
        _fill(canvas, size, CommyFlagPalette.seBlue);
        _nordicCross(canvas, size, CommyFlagPalette.seYellow, _crossThick);
      case _FlagDesign.no:
        _fill(canvas, size, CommyFlagPalette.noRed);
        _nordicCross(canvas, size, CommyFlagPalette.white, _crossThickWide);
        _nordicCross(canvas, size, CommyFlagPalette.noBlue, _crossThickInner);
      case _FlagDesign.ch:
        _fill(canvas, size, CommyFlagPalette.chRed);
        _swissCross(canvas, size);
      case _FlagDesign.jp:
        _fill(canvas, size, CommyFlagPalette.white);
        canvas.drawCircle(
          size.center(Offset.zero),
          size.height * _discRadius,
          Paint()..color = CommyFlagPalette.jpRed,
        );
      case _FlagDesign.eu:
        _fill(canvas, size, CommyFlagPalette.euBlue);
        _starRing(canvas, size);
      case _FlagDesign.us:
        _stripesAndCanton(canvas, size);
      case _FlagDesign.gb:
        _unionJack(canvas, size);
      case _FlagDesign.tr:
        _fill(canvas, size, CommyFlagPalette.trRed);
        _crescentAndStar(canvas, size);
    }
  }

  // --- Geometry of the flags themselves, as ratios of the 26 × 20 field. ---

  /// Arm of an ordinary Nordic cross, as a share of the height.
  static const double _crossThick = 0.28;

  /// Arm of the white Norwegian cross, which carries a blue one inside it.
  static const double _crossThickWide = 0.40;

  /// Arm of that inner blue cross.
  static const double _crossThickInner = 0.18;

  /// Where the vertical bar of a Nordic cross sits, as a share of the width.
  /// Offset towards the hoist — a centred one would be a Swiss flag.
  static const double _crossOffset = 0.36;

  /// Arm of the Swiss cross, as a share of the height.
  static const double _swissThick = 0.20;

  /// Half-length of one Swiss arm, as a share of the height.
  static const double _swissReach = 0.32;

  /// Radius of the Japanese disc, as a share of the height.
  static const double _discRadius = 0.30;

  /// Radius of the ring the twelve European stars stand on.
  static const double _ringRadius = 0.30;

  /// Radius of one of those stars.
  static const double _ringStar = 0.058;

  /// How many stripes the United States flag has.
  static const int _stripeCount = 13;

  /// How many of them the canton covers.
  static const int _cantonStripes = 7;

  /// Width of the canton, as a share of the width.
  static const double _cantonWidth = 0.42;

  /// Radius of one star inside the canton, as a share of the height.
  static const double _cantonStar = 0.032;

  /// Star grid inside the canton: four across, three down.
  static const int _cantonColumns = 4;

  /// Rows of that grid.
  static const int _cantonRows = 3;

  /// White saltire of the Union flag, as a share of the height.
  static const double _saltireWhite = 0.30;

  /// Red saltire drawn on top of it.
  static const double _saltireRed = 0.12;

  /// White cross of the Union flag.
  static const double _georgeWhite = 0.36;

  /// Red cross drawn on top of it.
  static const double _georgeRed = 0.20;

  /// Radius of the Turkish crescent's outer circle.
  static const double _crescentOuter = 0.30;

  /// Radius of the circle bitten out of it.
  static const double _crescentInner = 0.24;

  /// Centre of the outer circle, as a share of the width.
  static const double _crescentX = 0.36;

  /// Centre of the inner one. The gap between the two makes the horns.
  static const double _crescentBiteX = 0.44;

  /// Centre of the Turkish star, as a share of the width.
  static const double _crescentStarX = 0.62;

  /// Radius of that star, as a share of the height.
  static const double _crescentStar = 0.15;

  /// Radius of the globe on the neutral chip, as a share of the height.
  static const double _globeRadius = 0.28;

  /// How wide the globe's meridian is, relative to the globe.
  static const double _globeMeridian = 0.42;

  // --- Painting primitives. ---

  void _fill(Canvas canvas, Size size, Color color) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  /// Paints [colors] as horizontal bands.
  ///
  /// Each band is drawn all the way to the bottom edge and the next one covers
  /// what it does not need, so two bands can never leave an antialiased seam
  /// between them — at 20 dp tall a half-pixel seam is a visible scratch.
  void _horizontal(
    Canvas canvas,
    Size size,
    List<Color> colors, [
    List<double>? weights,
  ]) {
    var offset = 0.0;
    for (var index = 0; index < colors.length; index++) {
      canvas.drawRect(
        Rect.fromLTRB(0, offset, size.width, size.height),
        Paint()..color = colors[index],
      );
      offset += size.height * _share(colors.length, weights, index);
    }
  }

  /// Paints [colors] as vertical bands, on the same principle as [_horizontal].
  void _vertical(
    Canvas canvas,
    Size size,
    List<Color> colors, [
    List<double>? weights,
  ]) {
    var offset = 0.0;
    for (var index = 0; index < colors.length; index++) {
      canvas.drawRect(
        Rect.fromLTRB(offset, 0, size.width, size.height),
        Paint()..color = colors[index],
      );
      offset += size.width * _share(colors.length, weights, index);
    }
  }

  static double _share(int count, List<double>? weights, int index) {
    if (weights == null) {
      return 1 / count;
    }
    var total = 0.0;
    for (final weight in weights) {
      total += weight;
    }
    return weights[index] / total;
  }

  void _nordicCross(Canvas canvas, Size size, Color color, double thickness) {
    final arm = size.height * thickness;
    final paint = Paint()..color = color;
    canvas
      ..drawRect(
        Rect.fromCenter(
          center: Offset(size.width * _crossOffset, size.height / 2),
          width: arm,
          height: size.height,
        ),
        paint,
      )
      ..drawRect(
        Rect.fromCenter(
          center: size.center(Offset.zero),
          width: size.width,
          height: arm,
        ),
        paint,
      );
  }

  void _swissCross(Canvas canvas, Size size) {
    final arm = size.height * _swissThick;
    final reach = size.height * _swissReach * 2;
    final centre = size.center(Offset.zero);
    final paint = Paint()..color = CommyFlagPalette.white;
    canvas
      ..drawRect(
        Rect.fromCenter(center: centre, width: arm, height: reach),
        paint,
      )
      ..drawRect(
        Rect.fromCenter(center: centre, width: reach, height: arm),
        paint,
      );
  }

  void _starRing(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final ring = size.height * _ringRadius;
    final paint = Paint()..color = CommyFlagPalette.euGold;
    for (var index = 0; index < 12; index++) {
      final angle = -math.pi / 2 + index * math.pi / 6;
      canvas.drawPath(
        _starPath(
          centre + Offset(ring * math.cos(angle), ring * math.sin(angle)),
          size.height * _ringStar,
        ),
        paint,
      );
    }
  }

  void _stripesAndCanton(Canvas canvas, Size size) {
    final stripe = size.height / _stripeCount;
    _fill(canvas, size, CommyFlagPalette.white);
    final red = Paint()..color = CommyFlagPalette.usRed;
    for (var index = 0; index < _stripeCount; index += 2) {
      canvas.drawRect(
        Rect.fromLTRB(
          0,
          stripe * index,
          size.width,
          stripe * (index + 1),
        ),
        red,
      );
    }

    final canton = Rect.fromLTWH(
      0,
      0,
      size.width * _cantonWidth,
      stripe * _cantonStripes,
    );
    canvas.drawRect(canton, Paint()..color = CommyFlagPalette.usBlue);

    final star = Paint()..color = CommyFlagPalette.white;
    for (var column = 0; column < _cantonColumns; column++) {
      for (var row = 0; row < _cantonRows; row++) {
        canvas.drawCircle(
          Offset(
            canton.width * (column + 1) / (_cantonColumns + 1),
            canton.height * (row + 1) / (_cantonRows + 1),
          ),
          size.height * _cantonStar,
          star,
        );
      }
    }
  }

  void _unionJack(Canvas canvas, Size size) {
    _fill(canvas, size, CommyFlagPalette.gbBlue);

    void saltire(Color color, double thickness) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = size.height * thickness
        ..style = PaintingStyle.stroke;
      canvas
        ..drawLine(Offset.zero, Offset(size.width, size.height), paint)
        ..drawLine(Offset(size.width, 0), Offset(0, size.height), paint);
    }

    void george(Color color, double thickness) {
      final arm = size.height * thickness;
      final paint = Paint()..color = color;
      canvas
        ..drawRect(
          Rect.fromCenter(
            center: size.center(Offset.zero),
            width: arm,
            height: size.height,
          ),
          paint,
        )
        ..drawRect(
          Rect.fromCenter(
            center: size.center(Offset.zero),
            width: size.width,
            height: arm,
          ),
          paint,
        );
    }

    saltire(CommyFlagPalette.white, _saltireWhite);
    saltire(CommyFlagPalette.gbRed, _saltireRed);
    george(CommyFlagPalette.white, _georgeWhite);
    george(CommyFlagPalette.gbRed, _georgeRed);
  }

  void _crescentAndStar(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final outer = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * _crescentX, middle),
          radius: size.height * _crescentOuter,
        ),
      );
    final bite = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * _crescentBiteX, middle),
          radius: size.height * _crescentInner,
        ),
      );
    final paint = Paint()..color = CommyFlagPalette.white;
    canvas
      ..drawPath(Path.combine(PathOperation.difference, outer, bite), paint)
      ..drawPath(
        _starPath(
          Offset(size.width * _crescentStarX, middle),
          size.height * _crescentStar,
        ),
        paint,
      );
  }

  void _paintNeutral(Canvas canvas, Size size) {
    _fill(canvas, size, neutralFill);
    final centre = size.center(Offset.zero);
    final radius = size.height * _globeRadius;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = CommySizes.borderThin
      ..color = neutralMark;
    canvas
      ..drawCircle(centre, radius, stroke)
      ..drawLine(
        Offset(centre.dx - radius, centre.dy),
        Offset(centre.dx + radius, centre.dy),
        stroke,
      )
      ..drawOval(
        Rect.fromCenter(
          center: centre,
          width: radius * 2 * _globeMeridian,
          height: radius * 2,
        ),
        stroke,
      );
  }

  /// A five-pointed star of radius [radius], one point up.
  static Path _starPath(Offset centre, double radius) {
    // The inner radius of a regular pentagram, to four places.
    const inner = 0.3820;
    final path = Path();
    for (var index = 0; index < 10; index++) {
      final reach = index.isEven ? radius : radius * inner;
      final angle = -math.pi / 2 + index * math.pi / 5;
      final point =
          centre + Offset(reach * math.cos(angle), reach * math.sin(angle));
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_FlagPainter oldDelegate) =>
      oldDelegate.design != design ||
      oldDelegate.radius != radius ||
      oldDelegate.edge != edge ||
      oldDelegate.neutralFill != neutralFill ||
      oldDelegate.neutralMark != neutralMark;
}
