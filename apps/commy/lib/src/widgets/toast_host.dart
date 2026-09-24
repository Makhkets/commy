import 'dart:async';

import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// The layer toasts are drawn on: the top of the window, over every route.
///
/// Toasts used to be floating `SnackBar`s, which put them at the bottom —
/// over the connect button and the list, the part of the screen the thumb is
/// on — and the owner asked for them at the top (2026-09-24), under the
/// status bar, where a phone shows everything else it has to say.
///
/// It sits in `MaterialApp.builder`, above the navigator, so a toast outlives
/// the sheet or the route that raised it: copying a link closes the menu that
/// asked, and the confirmation must not close with it.
///
/// One toast at a time. A new one replaces the current one instead of
/// queueing behind it — a result that waits three seconds for its turn lands
/// after the user has moved on. Swiping it up puts it away early, and
/// everything around the toast stays tappable: the layer only takes the
/// touches that land on the toast itself.
class ToastHost extends StatefulWidget {
  /// Wraps [child], the navigator.
  const ToastHost({required this.child, super.key});

  /// What the toasts are drawn over.
  final Widget child;

  /// The host above [context], or `null` when there is none — a bare widget
  /// pumped by a test.
  static ToastHostState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ToastScope>()?.host;

  @override
  State<ToastHost> createState() => ToastHostState();
}

/// The state of a [ToastHost]: what is up, and for how much longer.
class ToastHostState extends State<ToastHost>
    with SingleTickerProviderStateMixin {
  // Built up front, not lazily: a host torn down before its first toast
  // would otherwise create its ticker in `dispose`, from a dead element.
  late final AnimationController _entrance;
  late final CurvedAnimation _curve;
  late final Animation<Offset> _slide;

  Timer? _timer;
  _ShownToast? _shown;

  /// Bumped by every toast, so a timer or an exit animation that belongs to
  /// a toast already replaced cannot take its successor down.
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(vsync: this);
    _curve = CurvedAnimation(
      parent: _entrance,
      curve: CommyMotion.standard.baseCurve,
    );
    // Its own height up: from just above where it rests, the fade covers
    // the rest of the way.
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(_curve);
  }

  /// Puts a toast up for [duration], replacing whatever is up.
  ///
  /// [onAction] is run after the toast is taken down, so the undo it offers
  /// is never answered by the same toast still sitting there.
  ///
  /// A toast with an action stays until it is answered, dismissed or
  /// replaced when a screen reader drives the device, because six seconds is
  /// not long enough to find the action by touch exploration. That is
  /// Material's rule for a `SnackBar` with an action, adopted on purpose —
  /// not carried over: the snack bars this replaced drew their action inside
  /// the content and passed none to Material, so they timed out regardless.
  /// It covers the automatic refresh's failure too: a toast nobody asked
  /// for, but its action is the only way to the reason, and the reader's
  /// dismiss gesture takes it down.
  void show({
    required String message,
    required CommyTone tone,
    required IconData icon,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _timer?.cancel();
    final serial = ++_serial;
    setState(() {
      _shown = _ShownToast(
        serial: serial,
        message: message,
        tone: tone,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                hide();
                onAction();
              },
      );
    });
    // Read per toast, not once: reduced motion can be switched on while the
    // app runs, and then every duration here is zero.
    final motion = context.motion;
    _curve.curve = motion.baseCurve;
    _entrance
      ..duration = motion.base
      ..reverseDuration = motion.fast;
    // From the top every time, a replacement included: the same sentence
    // twice in a row — a second ping of the same server — has to look like
    // a second answer, not like nothing happened.
    unawaited(_entrance.forward(from: 0));
    final waitsForReader = onAction != null &&
        (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);
    if (!waitsForReader) {
      _timer = Timer(duration, hide);
    }
  }

  /// Takes the current toast down, if there is one.
  void hide() {
    _timer?.cancel();
    _timer = null;
    if (_shown == null) {
      return;
    }
    final serial = _serial;
    _entrance.reverse().whenCompleteOrCancel(() {
      if (mounted && serial == _serial && _entrance.isDismissed) {
        setState(() => _shown = null);
      }
    });
  }

  /// Drops the toast a swipe already carried off screen.
  void _dismissed(int serial) {
    if (serial != _serial) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _entrance.value = 0;
    setState(() => _shown = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    return _ToastScope(
      host: this,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          widget.child,
          if (shown != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _layer(context, shown),
            ),
        ],
      ),
    );
  }

  Widget _layer(BuildContext context, _ShownToast shown) {
    final spacing = context.spacing;
    final inset = context.screenInset;

    // `SafeArea` for the status bar and a notch; the padding under it is the
    // gap between the toast and whatever the system draws up there.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(inset, spacing.s2, inset, 0),
        child: FadeTransition(
          opacity: _curve,
          child: SlideTransition(
            position: _slide,
            // There is no `Material` above the navigator, and without one the
            // toast's text falls back to the red-on-yellow error style.
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                container: true,
                liveRegion: true,
                onDismiss: hide,
                child: Dismissible(
                  key: ValueKey<int>(shown.serial),
                  direction: DismissDirection.up,
                  // Only the toast's own surface: `Toast` centres itself in
                  // the full width, and the empty sides of that box on a
                  // tablet belong to the screen underneath.
                  behavior: HitTestBehavior.deferToChild,
                  movementDuration: context.motion.base,
                  resizeDuration: null,
                  onDismissed: (_) => _dismissed(shown.serial),
                  child: Toast(
                    message: shown.message,
                    tone: shown.tone,
                    icon: shown.icon,
                    actionLabel: shown.actionLabel,
                    onAction: shown.onAction,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the toast currently up says.
@immutable
class _ShownToast {
  const _ShownToast({
    required this.serial,
    required this.message,
    required this.tone,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final int serial;
  final String message;
  final CommyTone tone;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Makes the host findable from anywhere below it, without a dependency: a
/// toast being shown must not rebuild every widget that can show one.
class _ToastScope extends InheritedWidget {
  const _ToastScope({required this.host, required super.child});

  final ToastHostState host;

  @override
  bool updateShouldNotify(_ToastScope oldWidget) => host != oldWidget.host;
}
