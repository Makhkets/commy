import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/widgets.dart';

/// Makes a hand-drawn control reachable from a keyboard or a D-pad, and
/// tells it when to show that it is the one with focus.
///
/// The switch, the checkbox, the radio and the segments are a
/// `GestureDetector` and a painting, because Material's own versions fight
/// the flat surface. A `GestureDetector` has no focus node and knows no
/// keys, so Tab went straight past every one of them: with a Bluetooth
/// keyboard, a D-pad or a Chromebook, none of the switches in Settings and
/// none of the routing modes could be reached at all.
///
/// [onActivate] is what Space, Enter and a D-pad centre do. `null` leaves the
/// control out of traversal, as a disabled control should be. [builder] is
/// told `true` only while focus is on the control *and* the last input was a
/// key: a tap focuses too, and a ring after every tap would be noise.
///
/// Internal to this package, like the controls' own painting: screens use
/// the controls, never this.
class CommyFocusable extends StatefulWidget {
  /// Wraps the control [builder] draws.
  const CommyFocusable({
    required this.onActivate,
    required this.builder,
    super.key,
  });

  /// What activating the control from a key does. `null` disables it.
  final VoidCallback? onActivate;

  /// Builds the control, with whether to draw its focus ring.
  final Widget Function(BuildContext context, {required bool isFocused})
      builder;

  /// The ring of a focused control: `border/strong`, the token that exists
  /// for focus, [CommySizes.borderThick] wide.
  ///
  /// Transparent rather than absent while [isFocused] is false, so that the
  /// box it is drawn on keeps one size and the control never shifts when
  /// focus arrives.
  static Border ring(CommyColors colors, {required bool isFocused}) =>
      Border.all(
        color: isFocused ? colors.borderStrong : CommyColors.transparent,
        width: CommySizes.borderThick,
      );

  @override
  State<CommyFocusable> createState() => _CommyFocusableState();
}

class _CommyFocusableState extends State<CommyFocusable> {
  bool _isFocused = false;

  void _activate() => widget.onActivate?.call();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onActivate != null;
    return FocusableActionDetector(
      enabled: enabled,
      actions: <Type, Action<Intent>>{
        // Space and a D-pad centre send the first, Enter the second.
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
      },
      onShowFocusHighlight: (value) {
        if (value != _isFocused) {
          setState(() => _isFocused = value);
        }
      },
      child: widget.builder(context, isFocused: enabled && _isFocused),
    );
  }
}
