import 'dart:async';
import 'dart:math' as math;

import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/components/molecules/latency_badge.dart';
import 'package:commy_ui/src/components/molecules/node_tag_line.dart';
import 'package:commy_ui/src/components/organisms/connect_state.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/typography.dart';
import 'package:flutter/material.dart';

/// Where the route broke, for the marker on its stop.
enum RouteBreak {
  /// The device itself: the VPN permission was refused, the helper is gone.
  device,

  /// On the way to the server: the configuration, the protocol, the core.
  server,

  /// Past the server: the tunnel is up, and nothing comes back through it.
  internet,
}

/// The signature of the product: the path the traffic takes, drawn as a line
/// with three stops — this device, the server, the internet
/// (docs/04-design-system.md §1 and §8, «Маршрут»).
///
/// A proxy client does exactly one thing — it leads traffic along this path —
/// so the line answers the question the main screen exists for, "is it
/// working, and through what", faster than any button could. Each leg is in
/// one of three shapes, and the shape says it as well as the colour does:
///
/// * dashed — there is no path here yet: traffic goes direct;
/// * a highlight travelling along it — the path is being built;
/// * solid — the path is there.
///
/// The leg that comes into being is drawn from its first stop to the next on
/// the `land` spring, and the stop it reaches lights up on `materialize`:
/// that is the one orchestrated moment of the product, once per connect,
/// never in a loop. A leg that goes away retracts the same way it came. A
/// failure puts a cross exactly on the stop where the route broke.
///
/// The server's stop is the server picker ([onServerTap]); the internet's
/// stop carries the check ([onCheck]) — each control sits beside what it
/// acts on. Under reduced motion nothing travels or draws: a leg being built
/// is shown half filled, and every change is a single frame.
class ConnectionRoute extends StatefulWidget {
  /// Creates the route.
  const ConnectionRoute({
    required this.state,
    required this.deviceLabel,
    required this.serverName,
    required this.internetLabel,
    this.flag,
    this.tags = const <NodeTag>[],
    this.latency,
    this.onServerTap,
    this.serverSemanticLabel,
    this.internetStatus,
    this.internetTone = CommyTone.neutral,
    this.checkLabel,
    this.onCheck,
    this.isChecking = false,
    this.breakAt,
    this.semanticLabel,
    super.key,
  });

  /// The route read out as one sentence — "Route: this device, Amsterdam 03,
  /// the internet. Connected". The stops' words are then left out of the
  /// tree, and only the two controls stay nodes of their own: the server
  /// picker and the access check. Already translated.
  final String? semanticLabel;

  /// The state of the tunnel the route draws.
  final ConnectState state;

  /// The first stop: "This device". Already translated.
  final String deviceLabel;

  /// The server traffic goes through, or would. Already translated when it
  /// is a sentence ("No server chosen") rather than a name.
  final String serverName;

  /// The last stop: "Internet". Already translated.
  final String internetLabel;

  /// The server's flag, drawn before its name. Usually a `CountryFlag`.
  final Widget? flag;

  /// The server's protocol line, as a server row shows it.
  final List<NodeTag> tags;

  /// Last measured round trip to the server, `null` when never measured.
  final Duration? latency;

  /// Opens the server picker. `null` draws no chevron and takes no tap.
  final VoidCallback? onServerTap;

  /// What the server's stop is announced as when it is a button: "Choose a
  /// server". Already translated.
  final String? serverSemanticLabel;

  /// One line under the internet stop: "Checking access…", "Online, 52 ms",
  /// "No answer". `null` draws nothing. Already translated.
  final String? internetStatus;

  /// The meaning of [internetStatus]: its colour, next to its words.
  final CommyTone internetTone;

  /// The label of the check action on the internet stop. Already
  /// translated.
  final String? checkLabel;

  /// Runs the access check. `null` hides the action.
  final VoidCallback? onCheck;

  /// Whether a check is running: the action shows a spinner and takes no tap.
  final bool isChecking;

  /// Where the route broke, when it did. Read with [state]: a break at the
  /// device or the server is a failed tunnel, a break at the internet is a
  /// tunnel that is up with nothing coming back through it.
  final RouteBreak? breakAt;

  @override
  State<ConnectionRoute> createState() => _ConnectionRouteState();
}

/// The three shapes of a leg.
enum _LegShape { dashed, building, solid }

/// What one leg looks like.
@immutable
class _Leg {
  const _Leg(this.shape, this.tone);

  final _LegShape shape;
  final CommyTone tone;
}

/// The three shapes of a stop.
enum _StopShape { ring, filled, marker }

/// What one stop looks like.
@immutable
class _Stop {
  const _Stop(this.shape, this.tone);

  final _StopShape shape;
  final CommyTone tone;
}

class _ConnectionRouteState extends State<ConnectionRoute>
    with SingleTickerProviderStateMixin {
  /// How much of the internet stop's row the check may take beside the word
  /// before it moves under it.
  static const double _actionShare = 0.6;

  late final AnimationController _sweep = AnimationController(vsync: this);

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  _Leg get _toServer {
    final widget = this.widget;
    return switch (widget.state) {
      ConnectState.starting =>
        const _Leg(_LegShape.building, CommyTone.connecting),
      ConnectState.checking ||
      ConnectState.connected =>
        const _Leg(_LegShape.solid, CommyTone.connected),
      ConnectState.error when widget.breakAt == RouteBreak.server =>
        const _Leg(_LegShape.solid, CommyTone.error),
      ConnectState.idle ||
      ConnectState.stopping ||
      ConnectState.error =>
        const _Leg(_LegShape.dashed, CommyTone.idle),
    };
  }

  _Leg get _toInternet {
    final widget = this.widget;
    return switch (widget.state) {
      ConnectState.checking =>
        const _Leg(_LegShape.building, CommyTone.connected),
      ConnectState.connected when widget.breakAt == RouteBreak.internet =>
        const _Leg(_LegShape.dashed, CommyTone.connecting),
      ConnectState.connected =>
        const _Leg(_LegShape.solid, CommyTone.connected),
      ConnectState.idle ||
      ConnectState.starting ||
      ConnectState.stopping ||
      ConnectState.error =>
        const _Leg(_LegShape.dashed, CommyTone.idle),
    };
  }

  _Stop get _device {
    final widget = this.widget;
    return switch (widget.state) {
      ConnectState.starting => const _Stop(
          _StopShape.filled,
          CommyTone.connecting,
        ),
      ConnectState.checking ||
      ConnectState.connected =>
        const _Stop(_StopShape.filled, CommyTone.connected),
      ConnectState.error when widget.breakAt == RouteBreak.device =>
        const _Stop(_StopShape.marker, CommyTone.error),
      ConnectState.idle ||
      ConnectState.stopping ||
      ConnectState.error =>
        const _Stop(_StopShape.ring, CommyTone.idle),
    };
  }

  _Stop get _server {
    final widget = this.widget;
    return switch (widget.state) {
      ConnectState.starting => const _Stop(
          _StopShape.ring,
          CommyTone.connecting,
        ),
      ConnectState.checking ||
      ConnectState.connected =>
        const _Stop(_StopShape.filled, CommyTone.connected),
      ConnectState.error when widget.breakAt == RouteBreak.server =>
        const _Stop(_StopShape.marker, CommyTone.error),
      ConnectState.idle ||
      ConnectState.stopping ||
      ConnectState.error =>
        const _Stop(_StopShape.ring, CommyTone.idle),
    };
  }

  _Stop get _internet {
    final widget = this.widget;
    return switch (widget.state) {
      ConnectState.checking => const _Stop(
          _StopShape.ring,
          CommyTone.connected,
        ),
      ConnectState.connected when widget.breakAt == RouteBreak.internet =>
        const _Stop(_StopShape.marker, CommyTone.connecting),
      ConnectState.connected =>
        const _Stop(_StopShape.filled, CommyTone.connected),
      ConnectState.idle ||
      ConnectState.starting ||
      ConnectState.stopping ||
      ConnectState.error =>
        const _Stop(_StopShape.ring, CommyTone.idle),
    };
  }

  /// Runs the travelling highlight while a leg is being built, and only then.
  void _syncSweep(bool building, Duration period) {
    if (!building || period == Duration.zero) {
      if (_sweep.isAnimating) {
        _sweep.stop();
      }
      return;
    }
    if (!_sweep.isAnimating || _sweep.duration != period) {
      _sweep.duration = period;
      unawaited(_sweep.repeat());
    }
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final motion = context.motion;
    final toServer = _toServer;
    final toInternet = _toInternet;
    _syncSweep(
      toServer.shape == _LegShape.building ||
          toInternet.shape == _LegShape.building,
      motion.sweep,
    );
    final colors = context.colors;
    final type = context.typography;
    final spacing = context.spacing;
    final firstLine = MediaQuery.textScalerOf(context).scale(
      type.body.fontSize! * type.body.height!,
    );

    // Read as one sentence, the route keeps its plain words out of the tree
    // so they are not heard twice; the two controls stay nodes of their own.
    final quiet = widget.semanticLabel != null;
    final device = _RouteRow(
      stop: _device,
      isServer: false,
      legOut: toServer,
      firstLineHeight: firstLine,
      sweep: _sweep,
      child: Padding(
        padding: EdgeInsets.only(bottom: spacing.s4),
        child: ExcludeSemantics(
          excluding: quiet,
          child: Text(
            widget.deviceLabel,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );

    final latency = widget.latency;
    final server = _RouteRow(
      stop: _server,
      isServer: true,
      legIn: toServer,
      legOut: toInternet,
      firstLineHeight: firstLine,
      sweep: _sweep,
      onTap: widget.onServerTap,
      semanticLabel: widget.serverSemanticLabel,
      value: widget.serverName,
      quiet: quiet,
      child: Padding(
        padding: EdgeInsets.only(bottom: spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (widget.flag != null) ...<Widget>[
                  widget.flag!,
                  SizedBox(width: spacing.s2),
                ],
                Expanded(
                  child: Text(
                    widget.serverName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: type.title3.copyWith(color: colors.textPrimary),
                  ),
                ),
                if (latency != null) ...<Widget>[
                  SizedBox(width: spacing.s2),
                  LatencyBadge(latency: latency),
                ],
                if (widget.onServerTap != null) ...<Widget>[
                  SizedBox(width: spacing.s1),
                  Icon(
                    CommyIcons.chevronDown,
                    size: CommySizes.iconControl,
                    color: colors.textSecondary,
                  ),
                ],
              ],
            ),
            if (widget.tags.isNotEmpty) ...<Widget>[
              SizedBox(height: spacing.s05),
              NodeTagLine(tags: widget.tags),
            ],
          ],
        ),
      ),
    );

    final status = widget.internetStatus;
    final check = widget.onCheck;
    final hasCheck = check != null && widget.checkLabel != null;
    // With the check beside it, the stop's first line is as tall as the
    // check's 48 dp target, so the dot, the word and the action share one
    // axis instead of the action hanging below the word it belongs to.
    final internetLine = hasCheck && firstLine < CommySizes.minTapTarget
        ? CommySizes.minTapTarget
        : firstLine;
    final labels = ExcludeSemantics(
      excluding: quiet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            widget.internetLabel,
            style: type.body.copyWith(color: colors.textSecondary),
          ),
          if (status != null)
            Text(
              status,
              style: type.caption.copyWith(
                color: widget.internetTone == CommyTone.neutral
                    ? colors.textSecondary
                    : widget.internetTone.foreground(colors),
              ),
            ),
        ],
      ),
    );
    final action = hasCheck
        ? _CheckAction(
            label: widget.checkLabel!,
            onPressed: widget.isChecking ? null : check,
            isChecking: widget.isChecking,
          )
        : null;
    final topPad = (internetLine - firstLine) / 2;
    Widget internetRow({required bool actionBeside}) => _RouteRow(
          stop: _internet,
          isServer: false,
          legIn: toInternet,
          firstLineHeight: internetLine,
          sweep: _sweep,
          child: action == null
              ? Padding(padding: EdgeInsets.only(top: topPad), child: labels)
              : actionBeside
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: topPad),
                            child: labels,
                          ),
                        ),
                        action,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsets.only(top: topPad),
                          child: labels,
                        ),
                        action,
                      ],
                    ),
        );

    // Beside the word while it fits in most of the row; under it when a
    // large text size makes the two compete for the same line. Measured
    // here, above the rows: a row sizes itself to its content, and a
    // layout callback cannot run inside that measurement.
    return LayoutBuilder(
      builder: (context, constraints) {
        final content =
            constraints.maxWidth - CommySizes.routeRail - spacing.s3;
        final beside = action == null ||
            _CheckAction.widthOf(context, widget.checkLabel!) <=
                content * _actionShare;
        final route = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            device,
            server,
            internetRow(actionBeside: beside),
          ],
        );
        final sentence = widget.semanticLabel;
        if (sentence == null) {
          return route;
        }
        return Semantics(container: true, label: sentence, child: route);
      },
    );
  }
}

/// One stop of the route and the half-legs above and below it.
class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.stop,
    required this.isServer,
    required this.firstLineHeight,
    required this.sweep,
    required this.child,
    this.legIn,
    this.legOut,
    this.onTap,
    this.semanticLabel,
    this.value,
    this.quiet = false,
  });

  final _Stop stop;
  final bool isServer;
  final double firstLineHeight;
  final Animation<double> sweep;
  final Widget child;
  final _Leg? legIn;
  final _Leg? legOut;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// What a tappable stop is set to, read after its label: the server's
  /// name after "Choose a server".
  final String? value;

  /// Whether the route is read as one sentence, so a stop with nothing to
  /// press keeps its words out of the tree.
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final dotCenter = firstLineHeight / 2;
    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: CommySizes.routeRail,
            child: _Rail(
              stop: stop,
              isServer: isServer,
              dotCenter: dotCenter,
              legIn: legIn,
              legOut: legOut,
              sweep: sweep,
            ),
          ),
          SizedBox(width: spacing.s3),
          Expanded(child: child),
        ],
      ),
    );

    final tap = onTap;
    if (tap == null) {
      return quiet ? ExcludeSemantics(child: row) : row;
    }
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      value: value,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: context.radii.blockAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap,
          borderRadius: context.radii.blockAll,
          // The button says its own label and value; the words inside it
          // would repeat the name.
          child: ExcludeSemantics(excluding: semanticLabel != null, child: row),
        ),
      ),
    );
  }
}

/// The rail of one row: the two half-legs, and the stop between them.
class _Rail extends StatelessWidget {
  const _Rail({
    required this.stop,
    required this.isServer,
    required this.dotCenter,
    required this.sweep,
    this.legIn,
    this.legOut,
  });

  final _Stop stop;
  final bool isServer;
  final double dotCenter;
  final Animation<double> sweep;
  final _Leg? legIn;
  final _Leg? legOut;

  /// How much of a leg's length lies in the row it starts from. A leg runs
  /// from the middle of one row's first line, through the rest of that row,
  /// into the top of the next row's first line; most of it is the first part.
  static const double _split = 0.8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final reduced = context.reduceMotion;
    final size = stop.shape == _StopShape.marker
        ? CommySizes.routeMarker
        : isServer
            ? CommySizes.routeDotServer
            : CommySizes.routeDot;

    Widget half(_Leg? leg, {required bool upper}) {
      if (leg == null) {
        return const SizedBox.shrink();
      }
      final drawn = leg.shape == _LegShape.solid ? 1.0 : 0.0;
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(end: drawn),
        duration: drawn == 1 ? motion.land : motion.gentle,
        curve: motion.springCurve,
        builder: (context, progress, _) => TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: leg.tone.solid(colors)),
          duration: motion.gentle,
          curve: motion.springCurve,
          builder: (context, color, _) => CustomPaint(
            painter: _LegPainter(
              color: color ?? leg.tone.solid(colors),
              dashColor: colors.statusIdleSolid,
              progress: upper
                  ? ((progress - _split) / (1 - _split)).clamp(0.0, 1.0)
                  : (progress / _split).clamp(0.0, 1.0),
              building: leg.shape == _LegShape.building,
              reduced: reduced,
              sweep: sweep,
              from: upper ? _split : 0,
              to: upper ? 1 : _split,
            ),
          ),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        // The legs stop at the stop's edge rather than under it, so a ring
        // is hollow on whatever it is drawn on — the canvas, a card, a sheet.
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: math.max(0, dotCenter - size / 2),
          child: half(legIn, upper: true),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: dotCenter + size / 2,
          bottom: 0,
          child: half(legOut, upper: false),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: dotCenter - size / 2,
          height: size,
          child: Center(
            child: _StopDot(stop: stop, size: size),
          ),
        ),
      ],
    );
  }
}

/// A stop: a ring, a filled dot, or the marker of a break.
class _StopDot extends StatelessWidget {
  const _StopDot({required this.stop, required this.size});

  final _Stop stop;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final motion = context.motion;
    final solid = stop.tone.solid(colors);
    final filled = stop.shape != _StopShape.ring;
    return AnimatedContainer(
      duration: motion.materialize,
      curve: motion.springCurve,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? solid : CommyColors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: filled ? CommyColors.transparent : solid,
          width: CommySizes.routeStroke,
        ),
      ),
      child: stop.shape == _StopShape.marker
          ? Icon(
              CommyIcons.close,
              size: CommySizes.iconInline - CommySizes.borderThick * 2,
              color: stop.tone.onSolid(colors),
            )
          : null,
    );
  }
}

/// One half-leg: dashes where there is no path, a solid stroke up to
/// [progress], and — while the leg is being built — a highlight travelling
/// down it.
class _LegPainter extends CustomPainter {
  _LegPainter({
    required this.color,
    required this.dashColor,
    required this.progress,
    required this.building,
    required this.reduced,
    required this.sweep,
    required this.from,
    required this.to,
  }) : super(repaint: building && !reduced ? sweep : null);

  final Color color;
  final Color dashColor;
  final double progress;
  final bool building;
  final bool reduced;
  final Animation<double> sweep;

  /// Where this half starts and ends along the whole leg, 0 to 1.
  final double from;
  final double to;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final height = size.height;
    if (height <= 0) {
      return;
    }
    final stroke = Paint()
      ..strokeWidth = CommySizes.routeStroke
      ..strokeCap = StrokeCap.round;

    // The dashes underneath everything: the path that is not there yet.
    final solidTo = height * progress;
    if (solidTo < height) {
      stroke.color = dashColor;
      const period = CommySizes.routeDash + CommySizes.routeDashGap;
      for (var y = solidTo; y < height; y += period) {
        final end = (y + CommySizes.routeDash).clamp(0.0, height);
        canvas.drawLine(Offset(x, y), Offset(x, end), stroke);
      }
    }

    if (solidTo > 0) {
      stroke.color = color;
      canvas.drawLine(Offset(x, 0), Offset(x, solidTo), stroke);
    }

    if (!building) {
      return;
    }
    stroke.color = color;
    if (reduced) {
      // Half filled and still: the leg is under way, without motion.
      final halfway = (0.5 - from) / (to - from);
      final end = (halfway.clamp(0.0, 1.0)) * height;
      if (end > 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, end), stroke);
      }
      return;
    }
    // The highlight covers a fraction of the whole leg and travels from its
    // first stop to its second; this half draws whatever part of it falls
    // inside [from, to].
    const length = CommySizes.routeSweepFraction;
    final head = sweep.value * (1 + length);
    final start = ((head - length - from) / (to - from)).clamp(0.0, 1.0);
    final end = ((head - from) / (to - from)).clamp(0.0, 1.0);
    if (end > start) {
      canvas.drawLine(
        Offset(x, start * height),
        Offset(x, end * height),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LegPainter old) =>
      old.color != color ||
      old.dashColor != dashColor ||
      old.progress != progress ||
      old.building != building ||
      old.reduced != reduced ||
      old.from != from ||
      old.to != to;
}

/// The check on the internet stop: a small text action, a spinner while it
/// runs.
class _CheckAction extends StatelessWidget {
  const _CheckAction({
    required this.label,
    required this.onPressed,
    required this.isChecking,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isChecking;

  /// The width the action takes on one line: its padding, glyph, gap and
  /// label, at the text scale it will be drawn with.
  static double widthOf(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: context.typography.captionStrong),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    final spacing = context.spacing;
    return width + CommySizes.iconInline + spacing.s15 + spacing.s2 * 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final foreground = colors.textPrimary;
    // The visible label is a line of text; the target around it is the 48 dp
    // floor, reaching up and down into the row's own padding.
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: context.radii.controlAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: context.radii.controlAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: CommySizes.minTapTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (isChecking) ...<Widget>[
                    CommySpinner(
                      size: CommySizes.iconInline,
                      color: foreground,
                    ),
                    SizedBox(width: spacing.s15),
                  ] else ...<Widget>[
                    Icon(
                      CommyIcons.refresh,
                      size: CommySizes.iconInline,
                      color: foreground,
                    ),
                    SizedBox(width: spacing.s15),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: context.typography.captionStrong.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How one step of a [RouteSteps] went.
enum RouteStepState {
  /// Not reached: a step after the one that broke, or before the run.
  pending,

  /// Being checked right now.
  running,

  /// Checked and fine.
  passed,

  /// Checked and broken — where the route stops.
  failed,
}

/// One step of a [RouteSteps]: a layer that is checked in turn.
@immutable
class RouteStep {
  /// Creates a step.
  const RouteStep({required this.label, required this.state, this.detail});

  /// What the layer is: "Server name", "Port open". Already translated.
  final String label;

  /// How it went.
  final RouteStepState state;

  /// What it found: an address, a round trip, a host. Already formatted.
  final String? detail;
}

/// The same line as [ConnectionRoute], drawn through the layers of a check
/// instead of the three stops of a tunnel (docs/04-design-system.md §1): the
/// connection diagnosis walks the path to the server one layer at a time, and
/// each layer is a stop — solid up to where it is fine, a highlight
/// travelling into the one being checked, a cross on the one that broke, and
/// dashes past it, where nothing was judged.
class RouteSteps extends StatefulWidget {
  /// Creates the steps.
  const RouteSteps({required this.steps, super.key});

  /// The layers, in the order they are checked.
  final List<RouteStep> steps;

  @override
  State<RouteSteps> createState() => _RouteStepsState();
}

class _RouteStepsState extends State<RouteSteps>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(vsync: this);

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  static _Stop _stopOf(RouteStepState state) => switch (state) {
        RouteStepState.pending => const _Stop(_StopShape.ring, CommyTone.idle),
        RouteStepState.running =>
          const _Stop(_StopShape.ring, CommyTone.connecting),
        RouteStepState.passed =>
          const _Stop(_StopShape.filled, CommyTone.connected),
        RouteStepState.failed =>
          const _Stop(_StopShape.marker, CommyTone.error),
      };

  /// The leg from one step to the next, judged by where it arrives.
  static _Leg _legInto(RouteStepState from, RouteStepState to) {
    if (from != RouteStepState.passed) {
      return const _Leg(_LegShape.dashed, CommyTone.idle);
    }
    return switch (to) {
      RouteStepState.passed => const _Leg(_LegShape.solid, CommyTone.connected),
      RouteStepState.running =>
        const _Leg(_LegShape.building, CommyTone.connecting),
      RouteStepState.failed => const _Leg(_LegShape.solid, CommyTone.error),
      RouteStepState.pending => const _Leg(_LegShape.dashed, CommyTone.idle),
    };
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final colors = context.colors;
    final type = context.typography;
    final spacing = context.spacing;
    final firstLine = MediaQuery.textScalerOf(context).scale(
      type.body.fontSize! * type.body.height!,
    );
    final legs = <_Leg>[
      for (var index = 0; index + 1 < steps.length; index++)
        _legInto(steps[index].state, steps[index + 1].state),
    ];
    final building = legs.any((leg) => leg.shape == _LegShape.building);
    final period = context.motion.sweep;
    if (!building || period == Duration.zero) {
      if (_sweep.isAnimating) {
        _sweep.stop();
      }
    } else if (!_sweep.isAnimating || _sweep.duration != period) {
      _sweep.duration = period;
      unawaited(_sweep.repeat());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var index = 0; index < steps.length; index++)
          _RouteRow(
            stop: _stopOf(steps[index].state),
            isServer: false,
            legIn: index == 0 ? null : legs[index - 1],
            legOut: index == steps.length - 1 ? null : legs[index],
            firstLineHeight: firstLine,
            sweep: _sweep,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: index == steps.length - 1 ? 0 : spacing.s4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      steps[index].label,
                      style: type.body.copyWith(
                        color: steps[index].state == RouteStepState.pending
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                  ),
                  if (steps[index].detail != null) ...<Widget>[
                    SizedBox(width: spacing.s3),
                    Flexible(
                      child: Padding(
                        padding: EdgeInsets.only(top: spacing.s05),
                        child: Text(
                          steps[index].detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                            fontFeatures: CommyTypography.tabular,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
