import 'package:commy/gen/strings.g.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// What the panel said instead of sending servers.
///
/// A panel that will not serve this client answers with one entry addressed at
/// `0.0.0.0` and the reason where a server's name would be — "App not
/// supported", "Device limit reached", "Subscription expired". Until now the
/// app drew that entry as a server, with a flag and a ping button, and offered
/// to connect through it; the one thing it never did was tell the user what
/// the panel had actually said, which is the only useful part of the answer.
///
/// It sits in the card's node list rather than in the header, next to the rows
/// it is standing in for, the same way the measurement progress does — the
/// header is a fixed three controls (docs/05-ux-flows.md).
///
/// The text is the panel's own, untranslated. An admin writes it in whatever
/// language their users read, and a translation of it would be this app
/// inventing an explanation on someone else's behalf. The line above it is
/// ours and says whose words these are.
///
/// One case gets a line of ours below it as well: the device identifier
/// switched off. "App not supported" is word for word what a panel that
/// limits devices sends a client without `x-hwid`, and the person who turned
/// the switch off in settings is not going to connect the two on their own —
/// so the row says it, and puts the switch in reach.
class PanelNoticeRow extends StatelessWidget {
  /// Creates the row.
  const PanelNoticeRow({
    required this.messages,
    this.onSendDeviceId,
    super.key,
  });

  /// What the panel sent in place of servers, in its own order.
  final List<String> messages;

  /// Turns the device identifier on and asks the panel again. Set only while
  /// it is off.
  final VoidCallback? onSendDeviceId;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s4,
        vertical: spacing.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            CommyIcons.warning,
            size: CommySizes.iconControl,
            color: colors.statusConnecting,
          ),
          SizedBox(width: spacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  t.subscription.panelSaid,
                  style: context.typography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                SizedBox(height: spacing.s1),
                for (final message in messages)
                  Text(
                    message,
                    style: context.typography.body.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                if (onSendDeviceId != null) ...<Widget>[
                  SizedBox(height: spacing.s2),
                  Text(
                    t.subscription.deviceIdOff,
                    style: context.typography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: spacing.s2),
                  CommyButton(
                    label: t.subscription.sendDeviceId,
                    variant: CommyButtonVariant.secondary,
                    isCompact: true,
                    onPressed: onSendDeviceId,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
