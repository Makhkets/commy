import 'dart:async';

import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:commy_ui/src/tokens/springs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

/// Shrinks its child to 97 % the instant a finger lands on it, and lets it go
/// on a spring (docs/04-design-system.md §7.1).
///
/// The press answers `pointerdown`, not the tap: a button that waits for the
/// finger to lift before it shows anything feels dead. It listens with a raw
/// [Listener], so it never competes with the child's own gesture detector —
/// the tap still belongs to whatever is underneath, this only shows it.
///
/// The motion is a `snappy` spring (ζ 1, T 0.30) run from the value on screen
/// with the velocity it already has, so a press released halfway in comes back
/// from where it is and a quick double tap never jumps. A finger that slides
/// further than the touch slop — the start of a scroll — lets the press go.
///
/// Rows of a list do not use this: a scroll that starts on a row would shrink
/// it on every gesture. They answer with the grey highlight under the finger,
/// as iOS rows do. Under reduced motion nothing scales at all.
class CommyPressable extends StatefulWidget {
  /// Wraps [child].
  const CommyPressable({
    required this.child,
    this.enabled = true,
    super.key,
  });

  /// What shrinks.
  final Widget child;

  /// Whether a press shows. A disabled control does not answer a finger.
  final bool enabled;

  @override
  State<CommyPressable> createState() => _CommyPressableState();
}

class _CommyPressableState extends State<CommyPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
  );

  Offset? _down;

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _springTo(double target) {
    unawaited(
      _press.animateWith(
        SpringSimulation(
          CommySprings.snappy,
          _press.value,
          target,
          _press.velocity,
        ),
      ),
    );
  }

  void _onDown(PointerDownEvent event) {
    if (!widget.enabled || context.reduceMotion) {
      return;
    }
    _down = event.position;
    _springTo(1);
  }

  void _onMove(PointerMoveEvent event) {
    final down = _down;
    if (down == null) {
      return;
    }
    if ((event.position - down).distance > kTouchSlop) {
      _release();
    }
  }

  void _release() {
    if (_down == null) {
      return;
    }
    _down = null;
    _springTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (context, child) {
          final progress = _press.value;
          if (progress == 0) {
            return child!;
          }
          return Transform.scale(
            scale: 1 - (1 - CommySizes.pressScale) * progress,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
