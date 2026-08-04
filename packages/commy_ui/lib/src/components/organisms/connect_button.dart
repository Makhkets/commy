import 'dart:async';
import 'dart:math' as math;

import 'package:commy_ui/src/components/organisms/connect_state.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/connect_tokens.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/power_glyph.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The signature component of the product: one disc, one power sign.
///
/// **There is no text inside the button.** No label, no timer, no node name.
/// The power sign is understood without words and everything else would be
/// noise in the most visible place on screen. State is carried by the ring
/// colour, the glow and the progress arc — see [ConnectState].
///
/// Geometry is the spec table of docs/04-design-system.md verbatim: a 240 dp
/// container, a Ø208 halo, a Ø172 disc, a 62 dp glyph on a 2.2 stroke. The
/// tap target is the whole disc, which is 172 dp and therefore far past the
/// 48 dp floor.
///
/// The glow lives on a **stroked ring with no fill**, never on the disc. Hang
/// it on the translucent disc instead and the shadow bleeds through: a dark
/// disc with a glowing edge turns into a poisonous blob and takes the tone of
/// the whole screen with it.
///
/// Reduced motion is honoured: the arc stops rotating and the pulse holds at
/// full strength, so the states stay distinguishable while nothing moves.
class ConnectButton extends StatefulWidget {
  /// Creates a connect button.
  ///
  /// [semanticLabel] is the finished, translated name of the action — this
  /// package owns no strings. [semanticValue] is the state said in words, and
  /// it is what keeps the button usable when the ring colour is not: without
  /// it, colour would be the only carrier of meaning.
  const ConnectButton({
    required this.state,
    required this.onPressed,
    required this.semanticLabel,
    this.semanticValue,
    super.key,
  });

  /// What the button draws.
  final ConnectState state;

  /// Tap handler. `null` disables the button — no node selected yet.
  final VoidCallback? onPressed;

  /// Name of the action, announced to assistive technology.
  final String? semanticLabel;

  /// The current state in words, announced as the button's value.
  final String? semanticValue;

  @override
  State<ConnectButton> createState() => _ConnectButtonState();
}

class _ConnectButtonState extends State<ConnectButton>
    with TickerProviderStateMixin {
  late final AnimationController _arc = AnimationController(
    vsync: this,
    duration: CommyConnectTokens.arcRotation,
  );

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: CommyConnectTokens.pulsePeriod,
  );

  late final AnimationController _transition = AnimationController(
    vsync: this,
    value: 1,
    duration: CommyMotion.standard.connect,
  );

  late ConnectState _previous = widget.state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoops();
  }

  @override
  void didUpdateWidget(ConnectButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) {
      return;
    }
    _previous = oldWidget.state;
    final duration = context.motion.connect;
    if (duration == Duration.zero) {
      _transition.value = 1;
    } else {
      _transition.duration = duration;
      unawaited(_transition.forward(from: 0));
    }
    _syncLoops();
  }

  @override
  void dispose() {
    _arc.dispose();
    _pulse.dispose();
    _transition.dispose();
    super.dispose();
  }

  /// Starts or stops the two looping animations for the current state.
  ///
  /// Under reduced motion both are parked at zero: the arc still shows, it
  /// simply does not turn, and the glow holds steady at full strength.
  void _syncLoops() {
    final reduce = context.reduceMotion;
    if (reduce) {
      _arc
        ..stop()
        ..value = 0;
      _pulse
        ..stop()
        ..value = 0;
      return;
    }
    if (widget.state.showsArc) {
      if (!_arc.isAnimating) {
        unawaited(_arc.repeat());
      }
    } else {
      // Left where it stopped rather than reset: an arc that is fading out
      // must not jump back to twelve o'clock on its way.
      _arc.stop();
    }
    if (widget.state.pulses) {
      if (!_pulse.isAnimating) {
        unawaited(_pulse.repeat());
      }
    } else {
      _pulse.stop();
    }
  }

  /// Progress of the state change, curved and clamped.
  ///
  /// `motion/connect` is a spring and springs overshoot; colours and stroke
  /// widths must not be extrapolated past the state they are heading for.
  double get _progress {
    final value = context.motion.connectCurve.transform(_transition.value);
    return math.min(1, math.max(0, value));
  }

  /// How bright the glow burns this frame, between
  /// [CommyConnectTokens.pulseMinIntensity] and one.
  double get _glowIntensity {
    if (!widget.state.pulses || !_pulse.isAnimating) {
      return 1;
    }
    const floor = CommyConnectTokens.pulseMinIntensity;
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * _pulse.value);
    return floor + (1 - floor) * breath;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tokens = context.connectTokens;
    final from = _ConnectVisual.of(_previous, colors, tokens);
    final to = _ConnectVisual.of(widget.state, colors, tokens);

    return Semantics(
      button: true,
      enabled: widget.onPressed != null,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      child: SizedBox.square(
        dimension: CommyConnectTokens.containerSize,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge(<Listenable>[
                  _arc,
                  _pulse,
                  _transition,
                ]),
                builder: (context, child) => CustomPaint(
                  size: const Size.square(CommyConnectTokens.containerSize),
                  painter: _ConnectPainter(
                    visual: _ConnectVisual.lerp(from, to, _progress),
                    arcTurns: _arc.value,
                    glowIntensity: _glowIntensity,
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: CommyConnectTokens.discSize,
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onPressed,
                  customBorder: const CircleBorder(),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything the painter needs for one frame, in one immutable value.
///
/// Splitting the six states out of the painter is what lets a state change
/// animate at all: the button interpolates between two of these instead of
/// switching from one branch to another.
@immutable
class _ConnectVisual {
  const _ConnectVisual({
    required this.halo,
    required this.disc,
    required this.ring,
    required this.ringWidth,
    required this.glow,
    required this.glyph,
    required this.arc,
    required this.arcSweep,
  });

  /// The spec table of docs/04-design-system.md, one row per state.
  factory _ConnectVisual.of(
    ConnectState state,
    CommyColors colors,
    CommyConnectTokens tokens,
  ) {
    return switch (state) {
      ConnectState.idle => _ConnectVisual(
          halo: colors.bgSurface,
          disc: colors.bgRaised,
          ring: colors.borderDefault,
          ringWidth: CommySizes.borderMedium,
          glow: CommyColors.transparent,
          glyph: colors.textSecondary,
          arc: CommyColors.transparent,
          arcSweep: 0,
        ),
      ConnectState.starting => _ConnectVisual(
          halo: colors.bgSurface,
          disc: colors.bgRaised,
          ring: colors.borderSubtle,
          ringWidth: CommySizes.borderMedium,
          glow: CommyColors.transparent,
          glyph: colors.statusConnecting,
          arc: colors.statusConnecting,
          arcSweep: CommyConnectTokens.startingArcSweep,
        ),
      ConnectState.checking => _ConnectVisual(
          halo: tokens.haloChecking,
          disc: colors.statusConnectedWash,
          ring: colors.statusConnected,
          ringWidth: CommySizes.borderMedium,
          glow: CommyColors.transparent,
          glyph: tokens.glyphChecking,
          arc: colors.statusConnected,
          arcSweep: CommyConnectTokens.checkingArcSweep,
        ),
      ConnectState.connected => _ConnectVisual(
          halo: tokens.haloConnected,
          disc: colors.statusConnectedWash,
          ring: colors.statusConnected,
          ringWidth: CommySizes.borderThick,
          glow: colors.statusConnectedGlow,
          glyph: colors.statusConnected,
          arc: CommyColors.transparent,
          arcSweep: 0,
        ),
      ConnectState.stopping => _ConnectVisual(
          halo: colors.bgSurface,
          disc: colors.bgRaised,
          ring: colors.statusIdle,
          ringWidth: CommySizes.borderMedium,
          glow: CommyColors.transparent,
          glyph: colors.textDisabled,
          arc: CommyColors.transparent,
          arcSweep: 0,
        ),
      ConnectState.error => _ConnectVisual(
          halo: tokens.haloError,
          disc: colors.statusErrorWash,
          ring: colors.statusError,
          ringWidth: CommySizes.borderThick,
          glow: colors.statusErrorGlow,
          glyph: colors.statusError,
          arc: CommyColors.transparent,
          arcSweep: 0,
        ),
    };
  }

  /// Interpolates between two states of the button.
  ///
  /// The sweep of the arc does not interpolate — an arc that grew from 90° to
  /// 270° would read as progress that is not there. It keeps whichever of the
  /// two states actually draws one, and the colour fades it in or out.
  factory _ConnectVisual.lerp(
    _ConnectVisual a,
    _ConnectVisual b,
    double t,
  ) {
    if (t >= 1) {
      return b;
    }
    if (t <= 0) {
      return a;
    }
    return _ConnectVisual(
      halo: Color.lerp(a.halo, b.halo, t)!,
      disc: Color.lerp(a.disc, b.disc, t)!,
      ring: Color.lerp(a.ring, b.ring, t)!,
      ringWidth: a.ringWidth + (b.ringWidth - a.ringWidth) * t,
      glow: Color.lerp(a.glow, b.glow, t)!,
      glyph: Color.lerp(a.glyph, b.glyph, t)!,
      arc: Color.lerp(a.arc, b.arc, t)!,
      arcSweep: b.arcSweep > 0 ? b.arcSweep : a.arcSweep,
    );
  }

  /// Fill of the Ø208 outer halo.
  final Color halo;

  /// Fill of the Ø172 disc.
  final Color disc;

  /// Colour of the ring sitting on the edge of the disc.
  final Color ring;

  /// Width of that ring: 1.5, or 2 when connected or errored.
  final double ringWidth;

  /// Colour of the glow, transparent in the four states that do not glow.
  final Color glow;

  /// Colour of the power sign.
  final Color glyph;

  /// Colour of the progress arc, transparent when there is none.
  final Color arc;

  /// Sweep of that arc in degrees: 270 while starting, 90 while checking.
  final double arcSweep;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ConnectVisual &&
          other.halo == halo &&
          other.disc == disc &&
          other.ring == ring &&
          other.ringWidth == ringWidth &&
          other.glow == glow &&
          other.glyph == glyph &&
          other.arc == arc &&
          other.arcSweep == arcSweep;

  @override
  int get hashCode => Object.hash(
        halo,
        disc,
        ring,
        ringWidth,
        glow,
        glyph,
        arc,
        arcSweep,
      );
}

/// Paints halo, glow, disc, ring, arc and glyph, in that order.
class _ConnectPainter extends CustomPainter {
  const _ConnectPainter({
    required this.visual,
    required this.arcTurns,
    required this.glowIntensity,
  });

  /// Colours and widths of this frame.
  final _ConnectVisual visual;

  /// Where the progress arc has turned to, in turns.
  final double arcTurns;

  /// Current strength of the pulse, between zero and one.
  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The ring straddles the edge of the disc rather than sitting inside it:
    // half the stroke over the fill, half over the halo. Measured off the
    // reference render — a 2 dp ring there covers radii 85 to 87.
    const ringRadius = CommyConnectTokens.discSize / 2;

    canvas.drawCircle(
      center,
      CommyConnectTokens.haloSize / 2,
      Paint()..color = visual.halo,
    );

    _paintGlow(canvas, center, ringRadius);

    canvas
      ..drawCircle(
        center,
        CommyConnectTokens.discSize / 2,
        Paint()..color = visual.disc,
      )
      ..drawCircle(
        center,
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = visual.ringWidth
          ..color = visual.ring,
      );

    _paintArc(canvas, center, ringRadius);
    _paintGlyph(canvas, center);
  }

  /// The glow, and the one rule that decides whether this component works.
  ///
  /// It is a **stroked ring with no fill**. A blurred filled circle would
  /// light the middle of the disc from behind and, because the disc is a
  /// translucent wash, the light would come straight through.
  void _paintGlow(Canvas canvas, Offset center, double ringRadius) {
    if (visual.glow.a <= 0 || glowIntensity <= 0) {
      return;
    }
    final sigma = Shadow.convertRadiusToSigma(CommyConnectTokens.glowBlur);
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = visual.ringWidth + CommyConnectTokens.glowSpread * 2
        ..color = visual.glow.withValues(alpha: visual.glow.a * glowIntensity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
  }

  /// The progress arc: 270° while starting, a shorter probe while checking.
  ///
  /// It starts at twelve o'clock and turns clockwise, one turn every 900 ms.
  void _paintArc(Canvas canvas, Offset center, double ringRadius) {
    if (visual.arc.a <= 0 || visual.arcSweep <= 0) {
      return;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius),
      -math.pi / 2 + arcTurns * 2 * math.pi,
      _radians(visual.arcSweep),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = visual.ringWidth
        ..strokeCap = StrokeCap.round
        ..color = visual.arc,
    );
  }

  /// The power sign, drawn in Lucide's 24-unit grid scaled up to 62 dp.
  void _paintGlyph(Canvas canvas, Offset center) {
    const half = CommyPowerGlyph.grid / 2;
    const scale = CommyConnectTokens.glyphSize / CommyPowerGlyph.grid;
    // The stroke is a physical 2.2 dp, so it has to be divided back out of
    // the scale the rest of the path is drawn at.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = CommyConnectTokens.glyphStroke / scale
      ..strokeCap = StrokeCap.round
      ..color = visual.glyph;

    canvas
      // Origin at the top-left of Lucide's grid, so the path below is its
      // own coordinates, unshifted and comparable with the source.
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale)
      ..translate(-half, -half)
      ..drawArc(
        Rect.fromCircle(
          center: const Offset(
            CommyPowerGlyph.centerX,
            CommyPowerGlyph.arcCenterY,
          ),
          radius: CommyPowerGlyph.arcRadius,
        ),
        _radians(CommyPowerGlyph.arcStartDegrees),
        _radians(CommyPowerGlyph.arcSweepDegrees),
        false,
        paint,
      )
      ..drawLine(
        const Offset(CommyPowerGlyph.centerX, CommyPowerGlyph.barTopY),
        const Offset(CommyPowerGlyph.centerX, CommyPowerGlyph.barBottomY),
        paint,
      )
      ..restore();
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  @override
  bool shouldRepaint(_ConnectPainter oldDelegate) =>
      oldDelegate.visual != visual ||
      oldDelegate.arcTurns != arcTurns ||
      oldDelegate.glowIntensity != glowIntensity;
}
