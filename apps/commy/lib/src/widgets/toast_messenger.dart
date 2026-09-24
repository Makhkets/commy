import 'package:commy/src/widgets/toast_host.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/widgets.dart';

/// Puts a [Toast] in front of the user, wherever they are.
///
/// Split out of `NoticeHost` because the tunnel is no longer the only thing
/// with something to say: copying a share link, or failing to, is a result
/// the user has to see too, and a second hand-rolled toast somewhere else
/// would drift away from this one within a release.
///
/// Where it appears — the top of the window — and how it comes and goes is
/// [ToastHost]'s business; this class only decides how long each kind of
/// result stays up.
abstract final class ToastMessenger {
  /// How long a one-line result stays up.
  ///
  /// Long enough to read a latency, short enough not to sit over the list.
  static const Duration duration = Duration(seconds: 3);

  /// How long a toast with something to press stays up.
  ///
  /// Longer than a plain result, and for one reason: three seconds is enough
  /// to read "rule removed" and not enough to decide you did not mean it,
  /// find the word and hit it.
  static const Duration actionDuration = Duration(seconds: 6);

  /// Shows [message], replacing whatever toast is currently up.
  ///
  /// [actionLabel] with [onAction] puts one pressable word at the end of the
  /// toast — an undo, in practice. Pressing it takes the toast down first
  /// and then runs [onAction].
  ///
  /// Does nothing when there is no [ToastHost] above [context] — which
  /// happens in tests that pump a bare widget, and must not crash them.
  static void show(
    BuildContext context, {
    required String message,
    required CommyTone tone,
    required IconData icon,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ToastHost.maybeOf(context)?.show(
      message: message,
      tone: tone,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: onAction == null ? duration : actionDuration,
    );
  }
}
