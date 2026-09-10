import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/rule_set_controller.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Exception E-2, with the address it will use printed above the button.
///
/// docs/09-security-privacy.md sets the terms and this screen keeps them: the
/// download happens only when the user presses Download, the source is theirs
/// to change — their own mirror included — and clearing the field removes the
/// ability to make the request at all. Nothing here fetches on open, on a
/// timer, or on the rules changing.
///
/// It offers the tags the user's own rules name, not a catalogue. A rule set
/// nobody references is a few megabytes downloaded to sit on disk, and a
/// catalogue is also a list of everything we would like you to want.
class RuleSetsScreen extends ConsumerWidget {
  /// Creates the screen.
  const RuleSetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final controller = ref.read(ruleSetControllerProvider.notifier);
    final action = ref.watch(ruleSetControllerProvider);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final policy =
        ref.watch(routingPolicyProvider).value ?? RoutingPolicy.defaults;
    final onDisk = <String, RuleSet>{
      for (final set in ref.watch(ruleSetsProvider).value ?? const <RuleSet>[])
        set.tag: set,
    };
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    final needed = RouteSectionBuilder.requiredRuleSets(
      routing: policy,
      platform: ref.watch(configPlatformProvider),
    );
    final spare = <String>[
      for (final tag in onDisk.keys)
        if (!needed.contains(tag)) tag,
    ]..sort();

    return AdaptiveScaffold(
      appBar: CommyAppBar.section(
        title: t.ruleSets.title,
        backSemanticLabel: t.a11y.back,
        onBack: () => context.go(AppRoutes.routing),
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: spacing.s10),
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(spacing.s4),
            child: Text(
              t.ruleSets.intro,
              style: context.typography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          SectionLabel(t.ruleSets.source),
          SettingsSection(
            children: <Widget>[
              SettingsTile(
                icon: CommyIcons.globe,
                title: t.ruleSets.sourceLabel,
                subtitle: settings.isRuleSetSourceEnabled
                    ? settings.ruleSetSource
                    : t.ruleSets.sourceOff,
                isMonospaceSubtitle: settings.isRuleSetSourceEnabled,
                onTap: () => unawaited(_editSource(context, ref, settings)),
              ),
            ],
          ),
          SectionLabel(t.ruleSets.needed),
          if (needed.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s4),
              child: EmptyState(
                icon: CommyIcons.routing,
                title: t.ruleSets.noneNeeded,
                message: t.ruleSets.noneNeededBody,
                actionLabel: t.routing.title,
                onAction: () => context.go(AppRoutes.routing),
              ),
            )
          else
            SettingsSection(
              children: <Widget>[
                for (final tag in needed)
                  _RuleSetTile(
                    tag: tag,
                    stored: onDisk[tag],
                    now: now,
                    isDownloading: action.downloadingTag == tag,
                    canDownload: settings.isRuleSetSourceEnabled &&
                        !action.isBusy,
                    onDownload: () => unawaited(_download(context, ref, tag)),
                    onDelete: onDisk.containsKey(tag)
                        ? () => unawaited(
                              _confirmDelete(context, controller, tag),
                            )
                        : null,
                  ),
              ],
            ),
          if (spare.isNotEmpty) ...<Widget>[
            SectionLabel(t.ruleSets.onDisk),
            SettingsSection(
              children: <Widget>[
                for (final tag in spare)
                  _RuleSetTile(
                    tag: tag,
                    stored: onDisk[tag],
                    now: now,
                    isDownloading: false,
                    canDownload: false,
                    isUnused: true,
                    onDelete: () =>
                        unawaited(_confirmDelete(context, controller, tag)),
                  ),
              ],
            ),
          ],
          SizedBox(height: spacing.s6),
        ],
      ),
    );
  }

  /// Downloads one set and says which of the two things happened.
  Future<void> _download(
    BuildContext context,
    WidgetRef ref,
    String tag,
  ) async {
    final t = Translations.of(context);
    final ok = await ref.read(ruleSetControllerProvider.notifier).download(tag);
    if (!context.mounted || !ok) {
      return;
    }
    ToastMessenger.show(
      context,
      message: t.ruleSets.downloaded(tag: tag),
      tone: CommyTone.connected,
      icon: CommyIcons.success,
    );
  }

  /// Edits the address template, refusing one no request could be made from.
  Future<void> _editSource(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final t = Translations.of(context);
    final edited = await CommySheet.show<String>(
      context: context,
      title: t.ruleSets.source,
      builder: (context) => _SourceSheet(current: settings.ruleSetSource),
    );
    if (edited == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setRuleSetSource(edited);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    RuleSetController controller,
    String tag,
  ) async {
    final t = Translations.of(context);
    final confirmed = await CommySheet.show<bool>(
      context: context,
      title: t.ruleSets.deleteConfirm.title,
      builder: (context) => _DeleteConfirmation(
        body: t.ruleSets.deleteConfirm.body,
        confirmLabel: t.ruleSets.deleteConfirm.confirm,
        cancelLabel: t.ruleSets.deleteConfirm.cancel,
      ),
    );
    if (confirmed ?? false) {
      await controller.delete(tag);
    }
  }
}

/// One rule set: what it is, whether it is here, and what can be done to it.
class _RuleSetTile extends StatelessWidget {
  const _RuleSetTile({
    required this.tag,
    required this.stored,
    required this.now,
    required this.isDownloading,
    required this.canDownload,
    this.isUnused = false,
    this.onDownload,
    this.onDelete,
  });

  final String tag;
  final RuleSet? stored;
  final DateTime now;
  final bool isDownloading;
  final bool canDownload;
  final bool isUnused;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final spacing = context.spacing;
    final file = stored;

    return SettingsTile(
      icon: file == null ? CommyIcons.empty : CommyIcons.document,
      title: tag,
      subtitle: _subtitle(t),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (isDownloading)
            CommySpinner(semanticLabel: t.ruleSets.download)
          else if (onDownload != null)
            CommyButton(
              label: file == null ? t.ruleSets.download : t.ruleSets.update,
              variant: CommyButtonVariant.ghost,
              isCompact: true,
              onPressed: canDownload ? onDownload : null,
            ),
          if (onDelete != null) ...<Widget>[
            SizedBox(width: spacing.s1),
            CommyIconButton(
              icon: CommyIcons.delete,
              onPressed: onDelete,
              semanticLabel: t.ruleSets.deleteConfirm.confirm,
              tooltip: t.ruleSets.deleteConfirm.confirm,
            ),
          ],
        ],
      ),
    );
  }

  String _subtitle(Translations t) {
    final file = stored;
    if (file == null) {
      return t.ruleSets.missing;
    }
    final line = t.ruleSets.size(
      size: CommyByteFormat.bytes(file.sizeBytes),
      age: RelativeTime.coarse(file.ageAt(now), t),
    );
    return isUnused ? '$line · ${t.ruleSets.unused}' : line;
  }
}

/// The address template, checked before it is stored.
class _SourceSheet extends StatefulWidget {
  const _SourceSheet({required this.current});

  final String current;

  @override
  State<_SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<_SourceSheet> {
  late final TextEditingController _value = TextEditingController(
    text: widget.current,
  );
  bool _showError = false;

  @override
  void dispose() {
    _value.dispose();
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
            controller: _value,
            labelText: t.ruleSets.sourceLabel,
            helperText: t.ruleSets.sourceHelp(
              token: AppSettings.ruleSetTagToken,
            ),
            errorText: _showError ? t.ruleSets.sourceInvalid : null,
            autofocus: true,
            isMonospace: true,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              if (_showError) {
                setState(() => _showError = false);
              }
            },
          ),
          SizedBox(height: spacing.s5),
          CommyButton(label: t.common.save, onPressed: _submit),
          SizedBox(height: spacing.s4),
        ],
      ),
    );
  }

  /// An empty template is accepted and means "no downloads": rule R1 is
  /// better served by a user who can switch the exception off entirely than
  /// by one who has to trust that we never fire it.
  void _submit() {
    final value = _value.text.trim();
    if (value.isNotEmpty && !_isHttp(value)) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(value);
  }

  bool _isHttp(String raw) {
    final url = Uri.tryParse(raw.replaceAll(AppSettings.ruleSetTagToken, 'x'));
    if (url == null || url.host.isEmpty) {
      return false;
    }
    final scheme = url.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
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
