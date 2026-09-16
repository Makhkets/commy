import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/import/import_result_panel.dart';
import 'package:commy/src/screens/import/paste_sheet.dart';
import 'package:commy/src/screens/import/qr_scan_sheet.dart';
import 'package:commy/src/screens/import/subscription_sheet.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sheet behind the `+` in the header.
///
/// Four ways in, in the order docs/design-refs/07-import.png puts them: what
/// is already in the clipboard first, then subscription, QR and file. The
/// clipboard card is at the top because it is the path that gets a new user to
/// a working tunnel fastest, and the sixty-second target in
/// docs/00-vision.md is what this screen is designed against.
///
/// This is also where the four sheets' shared housekeeping lives: they all
/// write to one `importControllerProvider`, so [present] is what keeps the
/// result on it from outliving the route that produced it.
class ImportSheet extends ConsumerStatefulWidget {
  /// Creates the sheet body.
  const ImportSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => present(
        context,
        builder: (context) => const ImportSheet(),
      );

  /// Presents one of the import sheets and drops its result when it closes.
  ///
  /// The result belongs to the route that produced it. [ImportResultPanel]'s
  /// buttons clear it, but the scrim, the drag handle and the back gesture do
  /// not go through them — and until the controller is cleared, the next sheet
  /// opens on the last import's outcome with no way back to its own controls.
  /// Only the `+` on the home screen used to recover from that; a deep link
  /// and the first-run view open the same sheets and do not.
  ///
  /// The route's future is the only thing that knows about all four ways out,
  /// which is why the reset hangs off it rather than off a button.
  ///
  /// It covers an import that is still running, too, and not because it gets
  /// there first — a download dismissed halfway through lands seconds after
  /// this. `ImportController.reset` burns the ticket of whatever is in flight,
  /// so the result of an import whose sheet is gone is dropped where it is
  /// produced rather than written back in behind this call.
  static Future<void> present(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
  }) {
    final container = ProviderScope.containerOf(context, listen: false);
    return CommySheet.show<void>(
      context: context,
      title: title,
      builder: builder,
    ).whenComplete(
      () => container.read(importControllerProvider.notifier).reset(),
    );
  }

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
  /// Whether one of the three nested sheets is on top of this one.
  ///
  /// The sheet on top owns the import it started, result panel included.
  /// Without this the chooser under the scrim would swap its four tiles for a
  /// second copy of that panel, and a modal dragged away instead of closed
  /// would drop the user onto it with no route back to the choices.
  bool _childIsOpen = false;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final clipboard = ref.watch(clipboardPreviewProvider);
    final import = ref.watch(importControllerProvider);

    if (!_childIsOpen && (import.outcome != null || import.failure != null)) {
      return const ImportResultPanel();
    }

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
                t.import.title,
                style: context.typography.title1.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              SizedBox(height: spacing.s2),
              Text(
                t.home.empty.body,
                style: context.typography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: spacing.s4),
        clipboard.maybeWhen(
          data: (preview) => preview.hasContent
              ? _ClipboardCard(preview: preview)
              : const SizedBox.shrink(),
          orElse: () => const SizedBox.shrink(),
        ),
        SizedBox(height: spacing.s3),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.link,
              title: t.import.subscription.title,
              subtitle: t.import.subscription.subtitle,
              onTap: () =>
                  unawaited(_openChild(SubscriptionSheet.show(context))),
            ),
            SettingsTile(
              icon: CommyIcons.copy,
              title: t.import.paste.title,
              subtitle: t.import.paste.hint,
              onTap: () => unawaited(_openChild(PasteSheet.show(context))),
            ),
            SettingsTile(
              icon: CommyIcons.search,
              title: t.import.qr.title,
              subtitle: t.import.qr.permissionBody,
              onTap: () => unawaited(_openChild(QrScanSheet.show(context))),
            ),
            SettingsTile(
              icon: CommyIcons.document,
              title: t.import.file.title,
              subtitle: t.import.file.subtitle,
              onTap: () => unawaited(
                ref.read(importControllerProvider.notifier).importFile(),
              ),
            ),
          ],
        ),
        SizedBox(height: spacing.s4),
      ],
    );
  }

  /// Keeps the chooser out of the way until [sheet] is gone.
  ///
  /// [sheet] has already cleared the controller by the time it completes
  /// ([ImportSheet.present]), so what comes back here is the four tiles.
  Future<void> _openChild(Future<void> sheet) async {
    setState(() => _childIsOpen = true);
    try {
      await sheet;
    } finally {
      if (mounted) {
        setState(() => _childIsOpen = false);
      }
    }
  }
}

/// The highlighted card offering what is already in the clipboard.
class _ClipboardCard extends ConsumerWidget {
  const _ClipboardCard({required this.preview});

  final ClipboardPreview preview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final import = ref.watch(importControllerProvider);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: spacing.s4),
      child: Container(
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
                    t.import.clipboard.found(count: _countLabel(t)),
                    style: context.typography.captionStrong.copyWith(
                      color: colors.statusInfo,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.s3),
            // Redacted, not raw: the clipboard holds a UUID or a password and
            // the sheet is the last place it should be readable over a
            // shoulder (rule R3).
            Text(
              preview.redacted,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.typography.monoSmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
            SizedBox(height: spacing.s4),
            CommyButton(
              label: t.import.clipboard.paste,
              isLoading: import.isBusy,
              onPressed: () => unawaited(
                ref
                    .read(importControllerProvider.notifier)
                    .importText(preview.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _countLabel(Translations t) {
    final protocol = preview.protocol;
    if (preview.nodeCount == 1 && protocol != null) {
      return t.import.clipboard.one(protocol: protocol.wireName);
    }
    return t.import.clipboard.many(count: preview.nodeCount);
  }
}
