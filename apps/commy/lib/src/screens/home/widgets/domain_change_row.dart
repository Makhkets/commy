import 'package:commy/gen/strings.g.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// The question a provider's signed change of address puts to the user
/// (docs/adr/0019-subscription-domain-recovery.md).
///
/// The one decision of the whole recovery protocol that is never made for
/// the user. The signature says the provider's key signed the move; it cannot
/// say the key was not stolen, and a move the user did not expect is exactly
/// what a stolen key looks like. So the row names both addresses, says the
/// signature holds, and says what to do if the move is a surprise — and the
/// answer waits as long as the user does, on the card, above the servers.
class DomainChangeRow extends StatelessWidget {
  /// Creates the row.
  const DomainChangeRow({
    required this.subscription,
    required this.change,
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  /// The subscription that would move.
  final Subscription subscription;

  /// The signed move.
  final PendingDomainChange change;

  /// Moves the subscription.
  final VoidCallback? onAccept;

  /// Keeps it where it is.
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final manifest = change.manifest;
    final name = manifest.name ??
        subscription.recovery?.name ??
        t.subscription.recovery.provider;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s4,
        vertical: spacing.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            CommyIcons.lock,
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
                  t.subscription.recovery.changedTitle,
                  style: context.typography.body.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                SizedBox(height: spacing.s1),
                Text(
                  t.subscription.recovery.changedBody(
                    name: name,
                    from: subscription.url.host,
                    to: manifest.origin.host,
                  ),
                  style: context.typography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                SizedBox(height: spacing.s1),
                Text(
                  t.subscription.recovery.changedHint,
                  style: context.typography.caption.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
                SizedBox(height: spacing.s3),
                Wrap(
                  spacing: spacing.s2,
                  runSpacing: spacing.s2,
                  children: <Widget>[
                    CommyButton(
                      label: t.subscription.recovery.accept,
                      isCompact: true,
                      onPressed: onAccept,
                    ),
                    CommyButton(
                      label: t.subscription.recovery.decline,
                      variant: CommyButtonVariant.secondary,
                      isCompact: true,
                      onPressed: onDecline,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
