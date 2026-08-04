import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// An inline failure with the action that resolves it.
///
/// The architecture document is explicit: a failure without an action is an
/// unfinished failure. [actionLabel] is optional in the constructor only
/// because some banners are purely informational — an error tone without one
/// is a smell.
class ErrorBanner extends StatelessWidget {
  /// Creates a banner.
  const ErrorBanner({
    required this.message,
    this.tone = CommyTone.error,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.dismissSemanticLabel,
    super.key,
  });

  /// Human text of the failure. Already translated.
  final String message;

  /// Meaning the banner carries. Defaults to [CommyTone.error].
  final CommyTone tone;

  /// Optional short headline above [message]. Already translated.
  final String? title;

  /// Label of the resolving action. Already translated.
  final String? actionLabel;

  /// Called when the action is taken.
  final VoidCallback? onAction;

  /// When given, a dismiss cross appears and calls this.
  final VoidCallback? onDismiss;

  /// Label announced for the dismiss cross.
  final String? dismissSemanticLabel;

  IconData get _icon => switch (tone) {
        CommyTone.error => CommyIcons.error,
        CommyTone.connecting => CommyIcons.warning,
        CommyTone.connected => CommyIcons.success,
        CommyTone.info => CommyIcons.info,
        CommyTone.idle => CommyIcons.offline,
        CommyTone.neutral => CommyIcons.info,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final foreground = tone.foreground(colors);

    return Container(
      decoration: BoxDecoration(
        color: tone.wash(colors),
        borderRadius: context.radii.smAll,
        border: Border.all(color: foreground),
      ),
      padding: EdgeInsets.all(spacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_icon, size: CommySizes.iconControl, color: foreground),
          SizedBox(width: spacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (title != null) ...<Widget>[
                  Text(
                    title!,
                    style: type.bodyStrong.copyWith(color: foreground),
                  ),
                  SizedBox(height: spacing.s1),
                ],
                Text(
                  message,
                  style: type.body.copyWith(color: colors.textPrimary),
                ),
                if (actionLabel != null) ...<Widget>[
                  SizedBox(height: spacing.s2),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: type.bodyStrong.copyWith(color: foreground),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            CommyIconButton(
              icon: CommyIcons.close,
              onPressed: onDismiss,
              semanticLabel: dismissSemanticLabel ?? '',
              color: foreground,
              size: CommySizes.iconInline,
            ),
        ],
      ),
    );
  }
}
