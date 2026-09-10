import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// Puts a [Toast] in front of the user, wherever they are.
///
/// Split out of `NoticeHost` because the tunnel is no longer the only thing
/// with something to say: copying a share link, or failing to, is a result
/// the user has to see too, and a second hand-rolled `SnackBar` somewhere
/// else would drift away from this one within a release.
///
/// The `SnackBar` underneath contributes nothing visual — no colour, no
/// elevation, no padding — because the toast draws its own surface from the
/// tokens (rule R4).
abstract final class ToastMessenger {
  /// How long a one-line result stays up.
  ///
  /// Long enough to read a latency, short enough not to sit over the list.
  static const Duration duration = Duration(seconds: 3);

  /// Shows [message], replacing whatever toast is currently up.
  ///
  /// Does nothing when there is no messenger above [context] — which happens
  /// in tests that pump a bare widget, and must not crash them.
  static void show(
    BuildContext context, {
    required String message,
    required CommyTone tone,
    required IconData icon,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: CommyColors.transparent,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          duration: duration,
          content: Toast(message: message, tone: tone, icon: icon),
        ),
      );
  }
}
