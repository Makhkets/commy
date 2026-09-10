import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/screens/import/subscription_sheet.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "…" menu of a subscription card.
///
/// Everything rare lives here — collapse, rename, copy the link, auto refresh,
/// the refresh interval, delete — because docs/05-ux-flows.md fixes the header
/// at exactly three visible controls and puts the rest behind this sheet. The
/// layout follows docs/design-refs/05-subscription-menu.png.
class SubscriptionMenuSheet extends ConsumerWidget {
  /// Creates the sheet body.
  const SubscriptionMenuSheet({required this.subscription, super.key});

  /// The subscription the menu acts on, as it stood when the sheet opened.
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
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    // Renaming and the interval both write through the repository, so the
    // sheet follows the stored row rather than the copy it was opened with —
    // otherwise the header would keep showing the name the user just changed.
    final current = ref.watch(subscriptionsProvider).maybeWhen(
          data: (items) => items.firstWhere(
            (item) => item.id == subscription.id,
            orElse: () => subscription,
          ),
          orElse: () => subscription,
        );

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
                current.name,
                style: context.typography.title2.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: spacing.s1),
              Text(
                _subtitle(t, current, now),
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
              icon: current.isCollapsed
                  ? CommyIcons.chevronDown
                  : CommyIcons.chevronUp,
              title: current.isCollapsed
                  ? t.subscription.menu.expand
                  : t.subscription.menu.collapse,
              onTap: () {
                unawaited(
                  controller.setCollapsed(
                    id: current.id,
                    isCollapsed: !current.isCollapsed,
                  ),
                );
                Navigator.of(context).pop();
              },
            ),
            SettingsTile(
              icon: CommyIcons.edit,
              title: t.subscription.menu.rename,
              value: current.name,
              onTap: () => unawaited(_rename(context, controller, current)),
            ),
            SettingsTile(
              icon: CommyIcons.copy,
              title: t.subscription.menu.copyLink,
              onTap: () => unawaited(_copyLink(context, controller, current)),
            ),
            SettingsTile(
              icon: CommyIcons.refresh,
              title: t.subscription.menu.autoUpdate,
              trailing: CommySwitch(
                value: current.autoUpdate,
                semanticLabel: t.subscription.menu.autoUpdate,
                onChanged: (value) => unawaited(
                  controller.setAutoUpdate(current, value: value),
                ),
              ),
            ),
            SettingsTile(
              icon: CommyIcons.clock,
              title: t.subscription.menu.interval,
              value: RelativeTime.hours(current.updateInterval, t),
              onTap: () =>
                  unawaited(_pickInterval(context, controller, current)),
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

  String _subtitle(Translations t, Subscription current, DateTime now) {
    final last = current.lastUpdatedAt;
    if (last == null) {
      return t.subscription.never;
    }
    return t.subscription.updatedAgo(
      time: RelativeTime.coarse(now.difference(last), t),
    );
  }

  /// Asks for a new name and writes it, leaving the menu open.
  ///
  /// The menu stays because renaming is the one action here a user repeats —
  /// mistype, reopen, fix — and because the header above updates in place.
  Future<void> _rename(
    BuildContext context,
    SubscriptionController controller,
    Subscription current,
  ) async {
    final t = Translations.of(context);
    final name = await CommySheet.show<String>(
      context: context,
      title: t.subscription.rename.title,
      builder: (context) => _RenameSheet(initialName: current.name),
    );
    if (name == null) {
      return;
    }
    await controller.rename(current, name);
  }

  /// Copies the subscription URL and confirms that it happened.
  ///
  /// Silence here is expensive: the URL carries the access token, and a user
  /// who is not told the copy failed pastes an empty string somewhere else
  /// and blames the other end.
  Future<void> _copyLink(
    BuildContext context,
    SubscriptionController controller,
    Subscription current,
  ) async {
    final t = Translations.of(context);
    final navigator = Navigator.of(context);
    final copied = await controller.copyLink(current);
    if (context.mounted && copied) {
      ToastMessenger.show(
        context,
        message: t.subscription.linkCopied,
        tone: CommyTone.info,
        icon: CommyIcons.copy,
      );
    }
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Asks for a refresh interval and writes it.
  Future<void> _pickInterval(
    BuildContext context,
    SubscriptionController controller,
    Subscription current,
  ) async {
    final t = Translations.of(context);
    final hours = await CommySheet.show<int>(
      context: context,
      title: t.subscription.interval.title,
      builder: (context) => _IntervalSheet(subscription: current),
    );
    if (hours == null) {
      return;
    }
    await controller.setUpdateIntervalHours(current, hours);
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

/// One text field and a save button. Pops the trimmed name, or nothing.
class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initialName});

  final String initialName;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  bool _showError = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyTextField(
            controller: _name,
            labelText: t.subscription.rename.label,
            errorText: _showError ? t.subscription.rename.empty : null,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_showError) {
                setState(() => _showError = false);
              }
            },
            onSubmitted: (_) => _submit(),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(label: t.common.save, onPressed: _submit),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(name);
  }
}

/// The same four intervals the import sheet offers, so the two never disagree.
class _IntervalSheet extends StatefulWidget {
  const _IntervalSheet({required this.subscription});

  final Subscription subscription;

  @override
  State<_IntervalSheet> createState() => _IntervalSheetState();
}

class _IntervalSheetState extends State<_IntervalSheet> {
  late int _hours = _nearestOffered(widget.subscription.updateInterval.inHours);

  /// The stored figure can come from the panel's own header, which is free to
  /// suggest an hour count nobody offers here. Snapping to the closest button
  /// keeps the control from rendering with nothing selected.
  static int _nearestOffered(int hours) {
    var best = SubscriptionSheet.intervals.first;
    for (final offered in SubscriptionSheet.intervals) {
      if ((offered - hours).abs() < (best - hours).abs()) {
        best = offered;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            t.subscription.interval.body,
            style: context.typography.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s4),
          SegmentedControl<int>(
            value: _hours,
            segments: <SegmentedControlItem<int>>[
              for (final hours in SubscriptionSheet.intervals)
                SegmentedControlItem<int>(
                  value: hours,
                  label: RelativeTime.hours(Duration(hours: hours), t),
                ),
            ],
            onChanged: (hours) => setState(() => _hours = hours),
          ),
          SizedBox(height: spacing.s5),
          CommyButton(
            label: t.common.save,
            onPressed: () => Navigator.of(context).pop(_hours),
          ),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
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
