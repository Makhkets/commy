import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "…" menu of a subscription card.
///
/// Everything rare lives here — collapse, rename, copy the link, auto refresh,
/// delete — because docs/05-ux-flows.md fixes the header at exactly three
/// visible controls and puts the rest behind this sheet. The layout follows
/// docs/design-refs/05-subscription-menu.png.
class SubscriptionMenuSheet extends ConsumerWidget {
  /// Creates the sheet body.
  const SubscriptionMenuSheet({required this.subscription, super.key});

  /// The subscription the menu acts on.
  final Subscription subscription;

  /// Opens the menu as a bottom sheet, or a dialog on a wide window.
  static Future<void> show({
    required BuildContext context,
    required Subscription subscription,
  }) {
    return CommySheet.show<void>(
      context: context,
      builder: (context) => SubscriptionMenuSheet(subscription: subscription),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final controller = ref.read(subscriptionControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                subscription.name,
                style: context.typography.title2.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: spacing.s1),
              Text(
                _subtitle(t),
                style: context.typography.caption.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.s4),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: subscription.isCollapsed
                  ? CommyIcons.chevronDown
                  : CommyIcons.chevronUp,
              title: subscription.isCollapsed
                  ? t.subscription.menu.expand
                  : t.subscription.menu.collapse,
              onTap: () {
                unawaited(
                  controller.setCollapsed(
                    id: subscription.id,
                    isCollapsed: !subscription.isCollapsed,
                  ),
                );
                Navigator.of(context).pop();
              },
            ),
            SettingsTile(
              icon: CommyIcons.copy,
              title: t.subscription.menu.copyLink,
              onTap: () {
                unawaited(controller.copyLink(subscription));
                Navigator.of(context).pop();
              },
            ),
            SettingsTile(
              icon: CommyIcons.clock,
              title: t.subscription.menu.autoUpdate,
              value: subscription.autoUpdate
                  ? RelativeTime.hours(subscription.updateInterval, t)
                  : null,
              trailing: CommySwitch(
                value: subscription.autoUpdate,
                semanticLabel: t.subscription.menu.autoUpdate,
                onChanged: (value) => unawaited(
                  controller.setAutoUpdate(subscription, value: value),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.delete,
              title: t.subscription.menu.delete,
              tone: CommyTone.error,
              onTap: () => unawaited(_confirmDelete(context, controller)),
            ),
          ],
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }

  String _subtitle(Translations t) {
    final last = subscription.lastUpdatedAt;
    if (last == null) {
      return t.subscription.never;
    }
    return t.subscription.updatedAgo(
      time: RelativeTime.coarse(DateTime.now().difference(last), t),
    );
  }

  /// Deleting takes a credential with it, so it asks first and says what goes.
  Future<void> _confirmDelete(
    BuildContext context,
    SubscriptionController controller,
  ) async {
    final t = Translations.of(context);
    final navigator = Navigator.of(context);
    final confirmed = await CommySheet.show<bool>(
      context: context,
      title: t.subscription.deleteConfirm.title,
      builder: (context) => _DeleteConfirmation(
        body: t.subscription.deleteConfirm.body,
        confirmLabel: t.subscription.deleteConfirm.confirm,
        cancelLabel: t.subscription.deleteConfirm.cancel,
      ),
    );
    if (confirmed ?? false) {
      await controller.delete(subscription.id);
    }
    if (navigator.canPop()) {
      navigator.pop();
    }
  }
}

class _DeleteConfirmation extends StatelessWidget {
  const _DeleteConfirmation({
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String body;
  final String confirmLabel;
  final String cancelLabel;

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
            icon: CommyIcons.delete,
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
