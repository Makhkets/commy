import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy/src/screens/import/qr_scan_sheet.dart';
import 'package:commy/src/screens/import/subscription_sheet.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The empty state of the home screen, and the whole onboarding.
///
/// There is no carousel. docs/05-ux-flows.md: "Пустое состояние само по себе
/// объясняет, что делать" — and the second paragraph says out loud that the
/// emptiness is a product decision rather than a missing feature, because a
/// user who has met three other clients expects a free server list here.
///
/// Layout follows docs/design-refs/01-first-run.png: explanation, then the
/// clipboard offer if there is one, then the three remaining ways in.
///
/// Three of the five ways in open a sheet, which is what reports the import
/// afterwards. The other two — the file tile and the clipboard offer — have no
/// sheet of their own, so they only *start* the import and hand it back to the
/// screen: this view is torn down the moment an import lands a server, and a
/// result reported from here would be reported by a widget that is already
/// gone. The home screen owns both callbacks for that reason.
class FirstRunView extends ConsumerWidget {
  /// Creates the view.
  const FirstRunView({
    required this.onImportFile,
    required this.onPasteAndConnect,
    super.key,
  });

  /// Picks a config file and imports it.
  final VoidCallback onImportFile;

  /// Imports the clipboard text handed back, then connects to what it held.
  final ValueChanged<String> onPasteAndConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final clipboard = ref.watch(clipboardPreviewProvider).value;
    final state = ref.watch(importControllerProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(spacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: EmptyState(
                icon: CommyIcons.empty,
                title: t.home.empty.title,
                message: t.home.empty.body,
              ),
            ),
            if (clipboard != null && clipboard.hasContent) ...<Widget>[
              _ClipboardOffer(
                preview: clipboard,
                isBusy: state.isBusy,
                onPaste: () => onPasteAndConnect(clipboard.text),
              ),
              SizedBox(height: spacing.s3),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: _ImportChoice(
                    icon: CommyIcons.link,
                    label: t.home.empty.subscription,
                    onTap: () => unawaited(SubscriptionSheet.show(context)),
                  ),
                ),
                SizedBox(width: spacing.s2),
                Expanded(
                  child: _ImportChoice(
                    icon: CommyIcons.search,
                    label: t.home.empty.scan,
                    onTap: () => unawaited(QrScanSheet.show(context)),
                  ),
                ),
                SizedBox(width: spacing.s2),
                Expanded(
                  child: _ImportChoice(
                    icon: CommyIcons.document,
                    label: t.home.empty.file,
                    onTap: onImportFile,
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.s2),
            CommyButton(
              label: t.home.empty.paste,
              variant: CommyButtonVariant.ghost,
              icon: CommyIcons.copy,
              onPressed: () => unawaited(PasteSheet.show(context)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The highlighted "there is already a link in your clipboard" card.
class _ClipboardOffer extends StatelessWidget {
  const _ClipboardOffer({
    required this.preview,
    required this.isBusy,
    required this.onPaste,
  });

  final ClipboardPreview preview;
  final bool isBusy;

  /// Import, then hand the first server straight to the connect flow.
  ///
  /// This is the sixty-second path from docs/00-vision.md compressed into one
  /// tap: nothing else on this screen gets the user to a running tunnel with
  /// fewer decisions.
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Container(
      decoration: BoxDecoration(
        color: colors.statusInfoWash,
        borderRadius: context.radii.lgAll,
      ),
      padding: EdgeInsets.all(spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                CommyIcons.copy,
                size: CommySizes.iconControl,
                color: colors.statusInfo,
              ),
              SizedBox(width: spacing.s2),
              Expanded(
                child: Text(
                  t.home.empty.clipboardFound,
                  style: context.typography.captionStrong.copyWith(
                    color: colors.statusInfo,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.s3),
          Text(
            preview.redacted,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typography.monoSmall.copyWith(
              color: colors.textSecondary,
            ),
          ),
          SizedBox(height: spacing.s4),
          CommyButton(
            label: t.home.empty.pasteAndConnect,
            isLoading: isBusy,
            onPressed: onPaste,
          ),
        ],
      ),
    );
  }
}

/// One of the three square buttons along the bottom.
class _ImportChoice extends StatelessWidget {
  const _ImportChoice({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;

    return Material(
      color: colors.bgSurface,
      borderRadius: radii.lgAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.s2,
            vertical: spacing.s4,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: CommySizes.iconControl,
                color: colors.textSecondary,
              ),
              SizedBox(height: spacing.s2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: context.typography.caption.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
