import 'package:commy_ui/src/components/commy_inline_action.dart';
import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A transient confirmation.
///
/// Deliberately a plain widget rather than a controller: how long a toast
/// stays and where it is anchored is the application's business, and this
/// package must not own an overlay. Screens push it through their own
/// `Overlay` or `ScaffoldMessenger`.
class Toast extends StatelessWidget {
  /// Creates a toast.
  const Toast({
    required this.message,
    this.tone = CommyTone.neutral,
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Text of the toast. Already translated.
  final String message;

  /// Meaning the toast carries.
  final CommyTone tone;

  /// Optional leading Lucide icon.
  final IconData? icon;

  /// Label of an optional action, typically "undo". Already translated.
  final String? actionLabel;

  /// Called when the action is taken.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final accent = tone.foreground(colors);

    // `Align` first, and it is not decoration. A `SnackBar` hands its content
    // a *tight* width, and a `ConstrainedBox` under a tight parent is obliged
    // to obey the parent — so `toastMaxWidth` did nothing at all: the toast
    // measured 738pt on a tablet and 1338pt on a desktop window, a banner
    // across the whole screen with its action a thousand points from the eye.
    // `Align` relaxes the width to loose, which is what lets the cap bite.
    //
    // The `SizedBox` then fills whatever is allowed, so a phone is unchanged
    // — 328pt of a 390pt window, exactly as before — and only a window wider
    // than the cap sees a difference.
    return Align(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CommySizes.toastMaxWidth),
        child: SizedBox(
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              color: colors.bgRaised,
              borderRadius: context.radii.smAll,
              border: Border.all(color: colors.borderDefault),
              boxShadow: context.elevation.level2,
            ),
            // No vertical padding on the toast itself: the message carries
            // it, so that the action beside it can take the toast's whole
            // height as its tap target. A one-line toast is 48 tall instead
            // of 46, and the action is 48 instead of the 22 of its word.
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: CommySizes.iconControl, color: accent),
                  SizedBox(width: spacing.s3),
                ],
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: spacing.s3),
                    child: Text(
                      message,
                      style: type.body.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                if (actionLabel != null) ...<Widget>[
                  SizedBox(width: spacing.s4),
                  CommyInlineAction(
                    label: actionLabel!,
                    onPressed: onAction,
                    color: accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
