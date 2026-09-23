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
/// An unrecognised or missing code is **not** an error state. A country we
/// have no drawing for gets the neutral chip with its two letters on it —
/// `KG`, `UZ` — which still answers "where is this server" and is the same on
/// every platform. No code at all draws the chip with a globe mark, because a
/// node whose country we could not guess is an ordinary node, and a red cross
/// next to its name would be a lie about its health.
///
/// Flags come in two kinds. The first nineteen are painted by hand in
/// [_FlagPainter]; everything added since is data — a [_FlagSpec] of bands
/// and marks in [_specs] — because the fortieth tricolour does not deserve a
/// method of its own.
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

  /// The code for the flag of the European Union — not a country, which is
  /// exactly why the auto-select group wears it: the group is no one place.
  static const String europeanUnion = 'EU';

  /// Whether a flag is drawn for [code], as opposed to the neutral chip.
  ///
  /// Screens use it to decide whether a flag is worth the horizontal space at
  /// all; nothing breaks when it returns false.
  static bool isSupported(String? code) =>
      _designOf(code) != null || _specOf(code) != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final design = _designOf(countryCode);
    final spec = design == null ? _specOf(countryCode) : null;
    final letters =
        design == null && spec == null ? _lettersOf(countryCode) : null;
    final flag = SizedBox(
      width: CommySizes.flagWidth,
      height: CommySizes.flagHeight,
      child: CustomPaint(
        painter: _FlagPainter(
          design: design,
          spec: spec,
          hasLetters: letters != null,
          radius: context.radii.flag,
          edge: colors.borderDefault,
          neutralFill: colors.bgOverlay,
          neutralMark: colors.textTertiary,
        ),
        child: letters == null
            ? null
            : Center(
                child: Text(
                  letters,
                  // A glyph in a fixed 26 × 20 box, not reading text: scaled
                  // with the system font it would leave the chip.
                  textScaler: TextScaler.noScaling,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: context.typography.label.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0,
                  ),
                ),
              ),
      ),
    );

    final label = semanticLabel;
    if (label == null) {
      return ExcludeSemantics(child: flag);
    }
    return Semantics(label: label, image: true, child: flag);
  }

  static _FlagSpec? _specOf(String? code) =>
      code == null ? null : _specs[code.trim().toUpperCase()];

  /// The two letters the neutral chip carries, or `null` for the globe.
  ///
  /// Only a well-formed alpha-2 code qualifies. Anything else — a country
  /// name, a blank, a three-letter code — is not something to print on a
  /// 26 dp chip, and the globe says "unknown" without a typo in it.
  static String? _lettersOf(String? code) {
    final trimmed = code?.trim().toUpperCase() ?? '';
    return _alpha2.hasMatch(trimmed) ? trimmed : null;
  }

  static final RegExp _alpha2 = RegExp(r'^[A-Z]{2}$');

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
      europeanUnion => _FlagDesign.eu,
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
    required this.spec,
    required this.hasLetters,
    required this.radius,
    required this.edge,
    required this.neutralFill,
    required this.neutralMark,
  });

  /// Which hand-painted flag to draw, or `null` when it is not one of them.
  final _FlagDesign? design;

  /// Which data-described flag to draw, when [design] is `null`.
  final _FlagSpec? spec;

  /// Whether the neutral chip carries the country's letters instead of the
  /// globe. The letters are a child widget; this only keeps the globe out
  /// from under them.
  final bool hasLetters;

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
    final data = spec;
    if (flag != null) {
      _paintField(canvas, size, flag);
    } else if (data != null) {
      data.paint(canvas, size);
    } else {
      _paintNeutral(canvas, size);
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

  static void _fill(Canvas canvas, Size size, Color color) {
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

  static void _unionJack(Canvas canvas, Size size) {
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
    if (hasLetters) {
      return;
    }
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
      oldDelegate.spec != spec ||
      oldDelegate.hasLetters != hasLetters ||
      oldDelegate.radius != radius ||
      oldDelegate.edge != edge ||
      oldDelegate.neutralFill != neutralFill ||
      oldDelegate.neutralMark != neutralMark;
}

/// A flag as data: a field of bands, then marks painted over it in order.
///
/// Every number in a spec is a share — of the width for `x`, of the height for
/// `y` and for every radius and thickness — so a flag is described once and
/// holds at any size. They are flag geometry, not design tokens, for the same
/// reason the ratios in [_FlagPainter] are.
///
/// At 26 × 20 a coat of arms is three pixels across. Where a flag carries one,
/// the spec draws the blob it reads as at that size — a shield-coloured box, a
/// disc — rather than pretending to detail nobody could see.
@immutable
class _FlagSpec {
  const _FlagSpec.horizontal(
    this.bands, {
    this.weights,
    this.marks = const <_Mark>[],
  }) : isVertical = false;

  const _FlagSpec.vertical(
    this.bands, {
    this.weights,
    this.marks = const <_Mark>[],
  }) : isVertical = true;

  /// Colours of the bands, hoist to fly or top to bottom. One colour is a
  /// plain field.
  final List<Color> bands;

  /// Relative sizes of [bands]; equal when `null`.
  final List<double>? weights;

  /// Whether the bands stand side by side rather than stack.
  final bool isVertical;

  /// What is painted over the bands, first to last.
  final List<_Mark> marks;

  void paint(Canvas canvas, Size size) {
    var offset = 0.0;
    for (var index = 0; index < bands.length; index++) {
      // To the far edge, like `_FlagPainter._horizontal`: the next band covers
      // what this one does not need, so no seam can open between them.
      canvas.drawRect(
        isVertical
            ? Rect.fromLTRB(offset, 0, size.width, size.height)
            : Rect.fromLTRB(0, offset, size.width, size.height),
        Paint()..color = bands[index],
      );
      offset += (isVertical ? size.width : size.height) *
          _FlagPainter._share(bands.length, weights, index);
    }
    for (final mark in marks) {
      mark.paint(canvas, size);
    }
  }
}

/// One shape painted over a flag's bands.
@immutable
sealed class _Mark {
  const _Mark();

  void paint(Canvas canvas, Size size);
}

/// A filled circle.
class _Disc extends _Mark {
  const _Disc(this.color, {required this.r, this.x = 0.5, this.y = 0.5});

  final Color color;
  final double x;
  final double y;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width * x, size.height * y),
      size.height * r,
      Paint()..color = color,
    );
  }
}

/// A circle drawn as a line.
class _Ring extends _Mark {
  const _Ring(this.color, {required this.r, required this.stroke});

  final Color color;
  final double r;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.height * r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * stroke
        ..color = color,
    );
  }
}

/// A slice of a disc, angles in radians clockwise from three o'clock.
class _Pie extends _Mark {
  const _Pie(
    this.color, {
    required this.r,
    required this.start,
    required this.sweep,
  });

  final Color color;
  final double r;
  final double start;
  final double sweep;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.height * r,
      ),
      start,
      sweep,
      true,
      Paint()..color = color,
    );
  }
}

/// A five-pointed star, one point up.
class _Star extends _Mark {
  const _Star(this.color, {required this.x, required this.y, required this.r});

  final Color color;
  final double x;
  final double y;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _FlagPainter._starPath(
        Offset(size.width * x, size.height * y),
        size.height * r,
      ),
      Paint()..color = color,
    );
  }
}

/// A filled rectangle between two corners.
class _Box extends _Mark {
  const _Box(this.color, this.left, this.top, this.right, this.bottom);

  final Color color;
  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTRB(
        size.width * left,
        size.height * top,
        size.width * right,
        size.height * bottom,
      ),
      Paint()..color = color,
    );
  }
}

/// A closed shape through [points], filled — or drawn as a line when
/// [stroke] is given.
class _Polygon extends _Mark {
  const _Polygon(this.color, this.points, {this.stroke});

  final Color color;
  final List<Offset> points;
  final double? stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = size.width * points[index].dx;
      final y = size.height * points[index].dy;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final paint = Paint()..color = color;
    final line = stroke;
    if (line != null) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.miter
        ..strokeWidth = size.height * line;
    }
    canvas.drawPath(path, paint);
  }
}

/// A cross of two bars meeting at ([x], [y]).
///
/// The reaches are half-lengths. Left at their defaults the bars run off the
/// flag, which is a Nordic cross when [x] sits towards the hoist and a Saint
/// George's cross when it does not.
class _Cross extends _Mark {
  const _Cross(
    this.color, {
    required this.thickness,
    this.x = 0.5,
    this.y = 0.5,
    this.reachX = 1,
    this.reachY = 1,
  });

  final Color color;
  final double thickness;
  final double x;
  final double y;
  final double reachX;
  final double reachY;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width * x, size.height * y);
    final arm = size.height * thickness;
    final paint = Paint()..color = color;
    canvas
      ..drawRect(
        Rect.fromCenter(
          center: centre,
          width: arm,
          height: size.height * reachY * 2,
        ),
        paint,
      )
      ..drawRect(
        Rect.fromCenter(
          center: centre,
          width: size.width * reachX * 2,
          height: arm,
        ),
        paint,
      );
  }
}

/// A crescent: one disc with another bitten out of it, [bite] further along.
class _Crescent extends _Mark {
  const _Crescent(
    this.color, {
    required this.x,
    required this.y,
    required this.outer,
    required this.inner,
    required this.bite,
  });

  final Color color;
  final double x;
  final double y;
  final double outer;
  final double inner;
  final double bite;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * x, size.height * y),
          radius: size.height * outer,
        ),
      );
    final bitten = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * (x + bite), size.height * y),
          radius: size.height * inner,
        ),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, whole, bitten),
      Paint()..color = color,
    );
  }
}

/// The Union flag in the upper hoist quarter, as Australia and New Zealand
/// fly it.
class _UnionCanton extends _Mark {
  const _UnionCanton();

  @override
  void paint(Canvas canvas, Size size) {
    final canton = Size(size.width / 2, size.height / 2);
    canvas
      ..save()
      ..clipRect(Offset.zero & canton);
    _FlagPainter._unionJack(canvas, canton);
    canvas.restore();
  }
}

const Color _white = CommyFlagPalette.white;
const Color _black = CommyFlagPalette.black;

/// Every flag described as data, by upper-case ISO 3166-1 alpha-2 code.
const Map<String, _FlagSpec> _specs = <String, _FlagSpec>{
  // --- Europe ---
  'CZ': _FlagSpec.horizontal(
    <Color>[_white, CommyFlagPalette.czRed],
    marks: <_Mark>[
      _Polygon(CommyFlagPalette.czBlue, <Offset>[
        Offset.zero,
        Offset(0.5, 0.5),
        Offset(0, 1),
      ]),
    ],
  ),
  'UA': _FlagSpec.horizontal(<Color>[
    CommyFlagPalette.uaBlue,
    CommyFlagPalette.uaYellow,
  ]),
  'EE': _FlagSpec.horizontal(<Color>[CommyFlagPalette.eeBlue, _black, _white]),
  'HU': _FlagSpec.horizontal(<Color>[
    CommyFlagPalette.huRed,
    _white,
    CommyFlagPalette.huGreen,
  ]),
  'BG': _FlagSpec.horizontal(<Color>[
    _white,
    CommyFlagPalette.bgGreen,
    CommyFlagPalette.bgRed,
  ]),
  'RO': _FlagSpec.vertical(<Color>[
    CommyFlagPalette.roBlue,
    CommyFlagPalette.roYellow,
    CommyFlagPalette.roRed,
  ]),
  'MD': _FlagSpec.vertical(
    <Color>[
      CommyFlagPalette.roBlue,
      CommyFlagPalette.roYellow,
      CommyFlagPalette.roRed,
    ],
    marks: <_Mark>[_Disc(CommyFlagPalette.mdEmblem, r: 0.14)],
  ),
  'LU': _FlagSpec.horizontal(<Color>[
    CommyFlagPalette.sgRed,
    _white,
    CommyFlagPalette.luBlue,
  ]),
  'BE': _FlagSpec.vertical(<Color>[
    _black,
    CommyFlagPalette.beYellow,
    CommyFlagPalette.beRed,
  ]),
  'IE': _FlagSpec.vertical(<Color>[
    CommyFlagPalette.ieGreen,
    _white,
    CommyFlagPalette.ieOrange,
  ]),
  'DK': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.dkRed],
    marks: <_Mark>[_Cross(_white, thickness: 0.15, x: 0.36)],
  ),
  'IS': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.isBlue],
    marks: <_Mark>[
      _Cross(_white, thickness: 0.24, x: 0.36),
      _Cross(CommyFlagPalette.isRed, thickness: 0.12, x: 0.36),
    ],
  ),
  'PT': _FlagSpec.vertical(
    <Color>[CommyFlagPalette.ptGreen, CommyFlagPalette.ptRed],
    weights: <double>[2, 3],
    marks: <_Mark>[
      _Disc(CommyFlagPalette.ptYellow, x: 0.4, r: 0.18),
      _Disc(_white, x: 0.4, r: 0.09),
    ],
  ),
  'GR': _FlagSpec.horizontal(
    <Color>[
      CommyFlagPalette.grBlue,
      _white,
      CommyFlagPalette.grBlue,
      _white,
      CommyFlagPalette.grBlue,
      _white,
      CommyFlagPalette.grBlue,
      _white,
      CommyFlagPalette.grBlue,
    ],
    marks: <_Mark>[
      _Box(CommyFlagPalette.grBlue, 0, 0, 0.4, 0.5556),
      _Cross(
        _white,
        thickness: 0.11,
        x: 0.2,
        y: 0.2778,
        reachX: 0.2,
        reachY: 0.2778,
      ),
    ],
  ),
  'RS': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.slavicRed, CommyFlagPalette.slavicBlue, _white],
    marks: <_Mark>[
      _Box(_white, 0.26, 0.24, 0.42, 0.76),
      _Box(CommyFlagPalette.slavicRed, 0.285, 0.28, 0.395, 0.72),
    ],
  ),
  'HR': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.slavicRed, _white, CommyFlagPalette.slavicBlue],
    marks: <_Mark>[
      _Box(_white, 0.4, 0.22, 0.6, 0.78),
      _Box(CommyFlagPalette.slavicRed, 0.425, 0.26, 0.575, 0.74),
      _Box(_white, 0.425, 0.26, 0.5, 0.5),
      _Box(_white, 0.5, 0.5, 0.575, 0.74),
    ],
  ),
  'SK': _FlagSpec.horizontal(
    <Color>[_white, CommyFlagPalette.slavicBlue, CommyFlagPalette.slavicRed],
    marks: <_Mark>[
      _Box(_white, 0.22, 0.2, 0.42, 0.8),
      _Box(CommyFlagPalette.slavicRed, 0.245, 0.24, 0.395, 0.76),
      _Cross(
        _white,
        thickness: 0.07,
        x: 0.32,
        y: 0.47,
        reachX: 0.05,
        reachY: 0.17,
      ),
    ],
  ),
  'SI': _FlagSpec.horizontal(
    <Color>[_white, CommyFlagPalette.slavicBlue, CommyFlagPalette.slavicRed],
    marks: <_Mark>[
      _Box(CommyFlagPalette.slavicRed, 0.17, 0.14, 0.35, 0.52),
      _Box(CommyFlagPalette.slavicBlue, 0.19, 0.17, 0.33, 0.49),
      _Polygon(_white, <Offset>[
        Offset(0.2, 0.47),
        Offset(0.26, 0.3),
        Offset(0.32, 0.47),
      ]),
    ],
  ),
  'BY': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.byRed, CommyFlagPalette.byGreen],
    weights: <double>[2, 1],
    marks: <_Mark>[
      _Box(_white, 0, 0, 0.12, 1),
      _Box(CommyFlagPalette.byRed, 0.04, 0, 0.08, 1),
    ],
  ),
  'CY': _FlagSpec.horizontal(
    <Color>[_white],
    marks: <_Mark>[
      _Polygon(CommyFlagPalette.cyCopper, <Offset>[
        Offset(0.2, 0.45),
        Offset(0.35, 0.35),
        Offset(0.5, 0.38),
        Offset(0.8, 0.25),
        Offset(0.62, 0.45),
        Offset(0.55, 0.55),
        Offset(0.4, 0.6),
        Offset(0.3, 0.55),
      ]),
      _Box(CommyFlagPalette.cyGreen, 0.33, 0.72, 0.48, 0.78),
      _Box(CommyFlagPalette.cyGreen, 0.52, 0.72, 0.67, 0.78),
    ],
  ),
  'MT': _FlagSpec.vertical(
    <Color>[_white, CommyFlagPalette.mtRed],
    marks: <_Mark>[
      _Cross(
        CommyFlagPalette.mtGrey,
        thickness: 0.07,
        x: 0.12,
        y: 0.2,
        reachX: 0.06,
        reachY: 0.11,
      ),
    ],
  ),
  'BA': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.baBlue],
    marks: <_Mark>[
      _Polygon(CommyFlagPalette.baYellow, <Offset>[
        Offset(0.28, 0),
        Offset(0.86, 0),
        Offset(0.86, 1),
      ]),
      _Star(_white, x: 0.258, y: 0.1, r: 0.06),
      _Star(_white, x: 0.374, y: 0.3, r: 0.06),
      _Star(_white, x: 0.49, y: 0.5, r: 0.06),
      _Star(_white, x: 0.606, y: 0.7, r: 0.06),
      _Star(_white, x: 0.722, y: 0.9, r: 0.06),
    ],
  ),

  // --- Caucasus and Central Asia ---
  'AM': _FlagSpec.horizontal(<Color>[
    CommyFlagPalette.amRed,
    CommyFlagPalette.amBlue,
    CommyFlagPalette.amOrange,
  ]),
  'GE': _FlagSpec.horizontal(
    <Color>[_white],
    marks: <_Mark>[
      _Cross(CommyFlagPalette.geRed, thickness: 0.2),
      _Cross(
        CommyFlagPalette.geRed,
        thickness: 0.07,
        x: 0.22,
        y: 0.22,
        reachX: 0.06,
        reachY: 0.1,
      ),
      _Cross(
        CommyFlagPalette.geRed,
        thickness: 0.07,
        x: 0.78,
        y: 0.22,
        reachX: 0.06,
        reachY: 0.1,
      ),
      _Cross(
        CommyFlagPalette.geRed,
        thickness: 0.07,
        x: 0.22,
        y: 0.78,
        reachX: 0.06,
        reachY: 0.1,
      ),
      _Cross(
        CommyFlagPalette.geRed,
        thickness: 0.07,
        x: 0.78,
        y: 0.78,
        reachX: 0.06,
        reachY: 0.1,
      ),
    ],
  ),
  'AZ': _FlagSpec.horizontal(
    <Color>[
      CommyFlagPalette.azBlue,
      CommyFlagPalette.azRed,
      CommyFlagPalette.azGreen,
    ],
    marks: <_Mark>[
      _Crescent(
        _white,
        x: 0.46,
        y: 0.5,
        outer: 0.15,
        inner: 0.125,
        bite: 0.035,
      ),
      _Star(_white, x: 0.58, y: 0.5, r: 0.07),
    ],
  ),
  'KZ': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.kzBlue],
    marks: <_Mark>[
      _Disc(CommyFlagPalette.kzGold, r: 0.2),
      _Box(CommyFlagPalette.kzGold, 0.04, 0, 0.09, 1),
    ],
  ),

  // --- Middle East and Asia ---
  'AE': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.aeGreen, _white, _black],
    marks: <_Mark>[_Box(CommyFlagPalette.aeRed, 0, 0, 0.27, 1)],
  ),
  'IL': _FlagSpec.horizontal(
    <Color>[_white],
    marks: <_Mark>[
      _Box(CommyFlagPalette.ilBlue, 0, 0.12, 1, 0.24),
      _Box(CommyFlagPalette.ilBlue, 0, 0.76, 1, 0.88),
      _Polygon(
        CommyFlagPalette.ilBlue,
        <Offset>[Offset(0.5, 0.31), Offset(0.635, 0.61), Offset(0.365, 0.61)],
        stroke: 0.05,
      ),
      _Polygon(
        CommyFlagPalette.ilBlue,
        <Offset>[Offset(0.5, 0.69), Offset(0.365, 0.39), Offset(0.635, 0.39)],
        stroke: 0.05,
      ),
    ],
  ),
  'IN': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.inSaffron, _white, CommyFlagPalette.inGreen],
    marks: <_Mark>[
      _Ring(CommyFlagPalette.inNavy, r: 0.13, stroke: 0.035),
      _Disc(CommyFlagPalette.inNavy, r: 0.035),
    ],
  ),
  'KR': _FlagSpec.horizontal(
    <Color>[_white],
    marks: <_Mark>[
      _Disc(CommyFlagPalette.krRed, r: 0.25),
      // The lower half of the taegeuk, tilted the way the real one leans.
      _Pie(CommyFlagPalette.krBlue, r: 0.25, start: 0.55, sweep: math.pi),
      // The four trigrams, as the dark blocks they read as at this size.
      _Polygon(_black, <Offset>[
        Offset(0.12, 0.26),
        Offset(0.22, 0.1),
        Offset(0.3, 0.17),
        Offset(0.2, 0.33),
      ]),
      _Polygon(_black, <Offset>[
        Offset(0.88, 0.26),
        Offset(0.78, 0.1),
        Offset(0.7, 0.17),
        Offset(0.8, 0.33),
      ]),
      _Polygon(_black, <Offset>[
        Offset(0.12, 0.74),
        Offset(0.22, 0.9),
        Offset(0.3, 0.83),
        Offset(0.2, 0.67),
      ]),
      _Polygon(_black, <Offset>[
        Offset(0.88, 0.74),
        Offset(0.78, 0.9),
        Offset(0.7, 0.83),
        Offset(0.8, 0.67),
      ]),
    ],
  ),
  'SG': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.sgRed, _white],
    marks: <_Mark>[
      _Crescent(
        _white,
        x: 0.2,
        y: 0.25,
        outer: 0.17,
        inner: 0.15,
        bite: 0.045,
      ),
      _Disc(_white, x: 0.36, y: 0.13, r: 0.028),
      _Disc(_white, x: 0.3, y: 0.22, r: 0.028),
      _Disc(_white, x: 0.42, y: 0.22, r: 0.028),
      _Disc(_white, x: 0.32, y: 0.35, r: 0.028),
      _Disc(_white, x: 0.4, y: 0.35, r: 0.028),
    ],
  ),
  'ID': _FlagSpec.horizontal(<Color>[CommyFlagPalette.sgRed, _white]),
  'HK': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.hkRed],
    marks: <_Mark>[
      // The bauhinia, as five petals round a centre.
      _Disc(_white, y: 0.34, r: 0.09),
      _Disc(_white, x: 0.617, y: 0.45, r: 0.09),
      _Disc(_white, x: 0.572, y: 0.63, r: 0.09),
      _Disc(_white, x: 0.428, y: 0.63, r: 0.09),
      _Disc(_white, x: 0.383, y: 0.45, r: 0.09),
      _Disc(_white, r: 0.06),
    ],
  ),
  'CN': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.cnRed],
    marks: <_Mark>[
      _Star(CommyFlagPalette.cnYellow, x: 0.2, y: 0.28, r: 0.18),
      _Star(CommyFlagPalette.cnYellow, x: 0.4, y: 0.1, r: 0.06),
      _Star(CommyFlagPalette.cnYellow, x: 0.47, y: 0.22, r: 0.06),
      _Star(CommyFlagPalette.cnYellow, x: 0.47, y: 0.38, r: 0.06),
      _Star(CommyFlagPalette.cnYellow, x: 0.4, y: 0.5, r: 0.06),
    ],
  ),
  'VN': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.cnRed],
    marks: <_Mark>[_Star(CommyFlagPalette.cnYellow, x: 0.5, y: 0.52, r: 0.3)],
  ),
  'TW': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.twRed],
    marks: <_Mark>[
      _Box(CommyFlagPalette.twBlue, 0, 0, 0.5, 0.5),
      _Disc(_white, x: 0.25, y: 0.25, r: 0.12),
    ],
  ),
  'TH': _FlagSpec.horizontal(
    <Color>[
      CommyFlagPalette.thRed,
      _white,
      CommyFlagPalette.thBlue,
      _white,
      CommyFlagPalette.thRed,
    ],
    weights: <double>[1, 1, 2, 1, 1],
  ),

  // --- Americas, Oceania, Africa ---
  'CA': _FlagSpec.vertical(
    <Color>[CommyFlagPalette.caRed, _white, CommyFlagPalette.caRed],
    weights: <double>[1, 2, 1],
    marks: <_Mark>[
      // The maple leaf, as the eleven-pointed outline that survives 12 px.
      _Polygon(CommyFlagPalette.caRed, <Offset>[
        Offset(0.5, 0.17),
        Offset(0.535, 0.3),
        Offset(0.575, 0.27),
        Offset(0.56, 0.45),
        Offset(0.625, 0.37),
        Offset(0.64, 0.42),
        Offset(0.7, 0.41),
        Offset(0.675, 0.52),
        Offset(0.695, 0.55),
        Offset(0.585, 0.67),
        Offset(0.6, 0.72),
        Offset(0.515, 0.7),
        Offset(0.515, 0.83),
        Offset(0.485, 0.83),
        Offset(0.485, 0.7),
        Offset(0.4, 0.72),
        Offset(0.415, 0.67),
        Offset(0.305, 0.55),
        Offset(0.325, 0.52),
        Offset(0.3, 0.41),
        Offset(0.36, 0.42),
        Offset(0.375, 0.37),
        Offset(0.44, 0.45),
        Offset(0.425, 0.27),
        Offset(0.465, 0.3),
      ]),
    ],
  ),
  'AU': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.auBlue],
    marks: <_Mark>[
      _UnionCanton(),
      _Star(_white, x: 0.25, y: 0.76, r: 0.13),
      _Star(_white, x: 0.75, y: 0.18, r: 0.06),
      _Star(_white, x: 0.62, y: 0.45, r: 0.06),
      _Star(_white, x: 0.87, y: 0.38, r: 0.06),
      _Star(_white, x: 0.75, y: 0.82, r: 0.06),
      _Disc(_white, x: 0.8, y: 0.55, r: 0.025),
    ],
  ),
  'NZ': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.auBlue],
    marks: <_Mark>[
      _UnionCanton(),
      _Star(_white, x: 0.75, y: 0.2, r: 0.085),
      _Star(CommyFlagPalette.nzRed, x: 0.75, y: 0.2, r: 0.055),
      _Star(_white, x: 0.64, y: 0.47, r: 0.085),
      _Star(CommyFlagPalette.nzRed, x: 0.64, y: 0.47, r: 0.055),
      _Star(_white, x: 0.86, y: 0.42, r: 0.085),
      _Star(CommyFlagPalette.nzRed, x: 0.86, y: 0.42, r: 0.055),
      _Star(_white, x: 0.75, y: 0.8, r: 0.085),
      _Star(CommyFlagPalette.nzRed, x: 0.75, y: 0.8, r: 0.055),
    ],
  ),
  'BR': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.brGreen],
    marks: <_Mark>[
      _Polygon(CommyFlagPalette.brYellow, <Offset>[
        Offset(0.5, 0.1),
        Offset(0.93, 0.5),
        Offset(0.5, 0.9),
        Offset(0.07, 0.5),
      ]),
      _Disc(CommyFlagPalette.brBlue, r: 0.2),
    ],
  ),
  'MX': _FlagSpec.vertical(
    <Color>[CommyFlagPalette.mxGreen, _white, CommyFlagPalette.mxRed],
    marks: <_Mark>[_Disc(CommyFlagPalette.mxEmblem, r: 0.11)],
  ),
  'AR': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.arBlue, _white, CommyFlagPalette.arBlue],
    marks: <_Mark>[_Disc(CommyFlagPalette.arSun, r: 0.1)],
  ),
  'CL': _FlagSpec.horizontal(
    <Color>[_white, CommyFlagPalette.clRed],
    marks: <_Mark>[
      _Box(CommyFlagPalette.clBlue, 0, 0, 0.34, 0.5),
      _Star(_white, x: 0.17, y: 0.25, r: 0.14),
    ],
  ),
  'ZA': _FlagSpec.horizontal(
    <Color>[CommyFlagPalette.zaRed, CommyFlagPalette.zaBlue],
    marks: <_Mark>[
      _Polygon(_white, <Offset>[
        Offset.zero,
        Offset(0.17, 0),
        Offset(0.52, 0.33),
        Offset(1, 0.33),
        Offset(1, 0.67),
        Offset(0.52, 0.67),
        Offset(0.17, 1),
        Offset(0, 1),
      ]),
      _Polygon(CommyFlagPalette.zaGreen, <Offset>[
        Offset.zero,
        Offset(0.09, 0),
        Offset(0.47, 0.4),
        Offset(1, 0.4),
        Offset(1, 0.6),
        Offset(0.47, 0.6),
        Offset(0.09, 1),
        Offset(0, 1),
      ]),
      _Polygon(CommyFlagPalette.zaGold, <Offset>[
        Offset(0, 0.13),
        Offset(0.36, 0.5),
        Offset(0, 0.87),
      ]),
      _Polygon(_black, <Offset>[
        Offset(0, 0.22),
        Offset(0.27, 0.5),
        Offset(0, 0.78),
      ]),
    ],
  ),
  'NG': _FlagSpec.vertical(<Color>[
    CommyFlagPalette.ngGreen,
    _white,
    CommyFlagPalette.ngGreen,
  ]),
};
