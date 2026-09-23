import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// Asks before something that cannot be taken back, and says what goes.
///
/// A bottom sheet rather than a dialog, like every other question this app
/// asks: the answer is under the thumb. The destructive choice is the danger
/// button on top, the way out a ghost button under it.
abstract final class ConfirmSheet {
  /// Shows the question. Resolves to `true` only for the confirm button;
  /// cancelling, a swipe down and a tap outside are all a no.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    required IconData icon,
  }) async {
    final confirmed = await CommySheet.show<bool>(
      context: context,
      title: title,
      builder: (context) => _Question(
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
      ),
    );
    return confirmed ?? false;
  }
}

class _Question extends StatelessWidget {
  const _Question({
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
  });

  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            body,
            style: context.typography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: confirmLabel,
            variant: CommyButtonVariant.danger,
            icon: icon,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          SizedBox(height: spacing.s2),
          CommyButton(
            label: cancelLabel,
            variant: CommyButtonVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }
}
