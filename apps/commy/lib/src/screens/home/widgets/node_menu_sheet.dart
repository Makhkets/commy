import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/node_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/node_descriptors.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The long-press menu of one server.
///
/// Measuring used to be the whole long-press gesture, which meant the two
/// other things a user does to a single server — take its link somewhere
/// else, and get rid of it — had nowhere to live. They live here.
class NodeMenuSheet extends ConsumerWidget {
  /// Creates the sheet body.
  const NodeMenuSheet({required this.node, super.key});

  /// The server the menu acts on.
  final ProxyNode node;

  /// Opens the menu as a bottom sheet, or a dialog on a wide window.
  static Future<void> show({
    required BuildContext context,
    required ProxyNode node,
  }) {
    return CommySheet.show<void>(
      context: context,
      builder: (context) => NodeMenuSheet(node: node),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

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
                node.name,
                style: context.typography.title2.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: spacing.s1),
              Text(
                NodeDescriptors.of(node).join(NodeTile.descriptorSeparator),
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
              icon: CommyIcons.diagnostics,
              title: t.node.measure,
              onTap: () {
                unawaited(
                  ref.read(tunnelControllerProvider.notifier).measure(node),
                );
                Navigator.of(context).pop();
              },
            ),
            SettingsTile(
              icon: CommyIcons.copy,
              title: t.node.copyLink,
              onTap: () => unawaited(_copyLink(context, ref)),
            ),
            SettingsTile(
              icon: CommyIcons.delete,
              title: t.node.delete,
              tone: CommyTone.error,
              onTap: () => unawaited(_confirmDelete(context, ref)),
            ),
          ],
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }

  /// Copies the share link and says which of the two things happened.
  ///
  /// Not every protocol has a link format. Closing the sheet with nothing on
  /// the clipboard and no word about it is the failure mode this avoids.
  Future<void> _copyLink(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final navigator = Navigator.of(context);
    final copied = await ref.read(nodeControllerProvider.notifier).copyLink(
          node,
        );
    if (!context.mounted) {
      return;
    }
    ToastMessenger.show(
      context,
      message: copied ? t.node.linkCopied : t.node.noLink,
      tone: copied ? CommyTone.info : CommyTone.error,
      icon: copied ? CommyIcons.copy : CommyIcons.warning,
    );
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  /// Deleting takes a credential with it, so it asks first and says what goes.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final controller = ref.read(nodeControllerProvider.notifier);
    final navigator = Navigator.of(context);
    final isLive = controller.isLive(node);
    final confirmed = await CommySheet.show<bool>(
      context: context,
      title: t.node.deleteConfirm.title,
      builder: (context) => _DeleteConfirmation(
        body: t.node.deleteConfirm.body,
        warning: isLive ? t.node.deleteConfirm.inUse : null,
        confirmLabel: t.node.deleteConfirm.confirm,
        cancelLabel: t.node.deleteConfirm.cancel,
      ),
    );
    if (confirmed ?? false) {
      await controller.delete(node);
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
    this.warning,
  });

  final String body;
  final String? warning;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final inUse = warning;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            body,
            style: context.typography.body.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (inUse != null) ...<Widget>[
            SizedBox(height: spacing.s3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  CommyIcons.warning,
                  size: CommySizes.iconControl,
                  color: colors.statusError,
                ),
                SizedBox(width: spacing.s2),
                Expanded(
                  child: Text(
                    inUse,
                    style: context.typography.caption.copyWith(
                      color: colors.statusError,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
