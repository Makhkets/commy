import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy/src/screens/import/qr_scan_sheet.dart';
import 'package:commy/src/screens/import/subscription_sheet.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The empty state of the home screen, and the whole onboarding.
///
/// There is no carousel. docs/05-ux-flows.md: "Пустое состояние само по себе
/// объясняет, что делать" — and the line under the answer says out loud that
/// the emptiness is a product decision rather than a missing feature, because
/// a user who has met three other clients expects a free server list here.
///
/// docs/04-design-system.md §9: the screen opens with what to do, "Add your
/// server", in the answer's type, and then shows the product rather than
/// describing it — the route at rest, with its middle stop empty: this
/// device, *no server added*, the internet. That is what Commy is, in one
/// picture, before the user has given it anything. Then the clipboard offer
/// when there is something to offer, and the ways in as one grouped list —
/// not three square tiles with an icon each, which is a template.
///
/// Three of the five ways in open a sheet, which is what reports the import
/// afterwards. The other two — the file row and the clipboard offer — have
/// no sheet of their own, so they only *start* the import and hand it back to
/// the screen: this view is torn down the moment an import lands a server,
/// and a result reported from here would be reported by a widget that is
/// already gone. The home screen owns both callbacks for that reason.
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
    final colors = context.colors;
    final type = context.typography;
    final clipboard = ref.watch(clipboardPreviewProvider).value;
    final state = ref.watch(importControllerProvider);

    return ListView(
      padding: EdgeInsets.only(top: spacing.s2, bottom: spacing.s10),
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  t.home.empty.title,
                  style: type.display.copyWith(color: colors.textPrimary),
                ),
              ),
              SizedBox(height: spacing.s2),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: CommySizes.readingWidth,
                ),
                child: Text(
                  t.home.empty.body,
                  style: type.bodyLarge.copyWith(color: colors.textSecondary),
                ),
              ),
              SizedBox(height: spacing.s6),
              // The product, shown before it is explained: a route whose
              // middle stop is still empty. Not interactive — there is
              // nothing to pick yet — and read out as one sentence.
              ConnectionRoute(
                semanticLabel: t.route.summary(
                  device: t.route.device,
                  server: t.route.noServer,
                  internet: t.route.internet,
                  state: t.route.idle,
                ),
                state: ConnectState.idle,
                deviceLabel: t.route.device,
                serverName: t.route.noServer,
                internetLabel: t.route.internet,
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.s6),
        if (clipboard != null && clipboard.hasContent) ...<Widget>[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing.s4),
            child: _ClipboardOffer(
              preview: clipboard,
              isBusy: state.isBusy,
              onPaste: () => onPasteAndConnect(clipboard.text),
            ),
          ),
          SizedBox(height: spacing.s3),
        ],
        SectionLabel(t.route.ways),
        SettingsSection(
          showsIcons: true,
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.link,
              title: t.home.empty.subscription,
              onTap: () => unawaited(SubscriptionSheet.show(context)),
            ),
            SettingsTile(
              icon: CommyIcons.qrCode,
              title: t.home.empty.scan,
              onTap: () => unawaited(QrScanSheet.show(context)),
            ),
            SettingsTile(
              icon: CommyIcons.document,
              title: t.home.empty.file,
              onTap: onImportFile,
            ),
            SettingsTile(
              icon: CommyIcons.copy,
              title: t.home.empty.paste,
              onTap: () => unawaited(PasteSheet.show(context)),
            ),
          ],
        ),
      ],
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
        borderRadius: context.radii.cardAll,
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
