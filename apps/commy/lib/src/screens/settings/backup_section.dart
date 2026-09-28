import 'dart:async';
import 'dart:typed_data';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/settings/backup_password_sheet.dart';
import 'package:commy/src/state/backup_controller.dart';
import 'package:commy/src/widgets/confirm_sheet.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// "Backup" on the settings screen: save everything to a file under a
/// password, or bring such a file back (G10, ADR-0017).
///
/// Two rows and no screen of their own. Each flow is a short chain of sheets —
/// password, the system's file dialog, a question before anything is replaced
/// — and every link in it can be walked away from without a trace: nothing is
/// written until the last "Replace", and a cancelled save leaves no file.
class BackupSection extends ConsumerWidget {
  /// Creates the section.
  const BackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final busy = ref.watch(backupControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(t.settings.backup.title),
        SettingsSection(
          children: <Widget>[
            SettingsTile(
              icon: CommyIcons.backup,
              title: t.settings.backup.export,
              subtitle: t.settings.backup.exportHint,
              onTap: busy ? null : () => unawaited(_guarded(ref, _export)),
            ),
            SettingsTile(
              icon: CommyIcons.restore,
              title: t.settings.backup.restore,
              subtitle: t.settings.backup.restoreHint,
              onTap: busy ? null : () => unawaited(_guarded(ref, _restore)),
            ),
          ],
        ),
      ],
    );
  }

  /// One flow at a time: a second tap before the first flow's sheet is up
  /// would start another beside it.
  Future<void> _guarded(
    WidgetRef ref,
    Future<void> Function(BuildContext context, WidgetRef ref) flow,
  ) async {
    final controller = ref.read(backupControllerProvider.notifier);
    if (!controller.beginFlow()) {
      return;
    }
    try {
      await flow(ref.context, ref);
    } finally {
      controller.endFlow();
    }
  }

  /// Password, seal, save.
  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final controller = ref.read(backupControllerProvider.notifier);
    ({Uint8List bytes, BackupSnapshot snapshot})? sealed;
    final done = await BackupPasswordSheet.show(
      context,
      title: t.settings.backup.password.exportTitle,
      body: t.settings.backup.password.exportBody,
      confirm: true,
      submitLabel: t.settings.backup.password.save,
      onSubmit: (password) async {
        switch (await controller.seal(password)) {
          case Ok(:final value):
            sealed = value;
            return null;
          case Err(:final failure):
            return FailureText.of(failure, t).message;
        }
      },
    );
    final result = sealed;
    if (!done || result == null || !context.mounted) {
      return;
    }
    final saved = await controller.save(
      result.bytes,
      madeAt: result.snapshot.createdAt,
      dialogTitle: t.settings.backup.fileTitle,
    );
    if (!context.mounted) {
      return;
    }
    switch (saved) {
      case Ok(value: true):
        ToastMessenger.show(
          context,
          message: t.settings.backup.saved(
            contents: _contents(t, result.snapshot),
          ),
          tone: CommyTone.connected,
          icon: CommyIcons.success,
        );
      case Ok(value: false):
        ToastMessenger.show(
          context,
          message: t.settings.backup.notSaved,
          tone: CommyTone.neutral,
          icon: CommyIcons.info,
        );
      case Err(:final failure):
        _sayFailure(context, t, failure);
    }
  }

  /// Pick, check, password, question, replace.
  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final t = Translations.of(context);
    final controller = ref.read(backupControllerProvider.notifier);
    final Uint8List bytes;
    switch (await controller.pick()) {
      case Ok(:final value?):
        bytes = value;
      case Ok():
        return;
      case Err(:final failure):
        if (context.mounted) {
          _sayFailure(context, t, failure);
        }
        return;
    }
    if (!context.mounted) {
      return;
    }
    // Turned away before a password is asked for: typing one into a sheet
    // for a file that was never going to open wastes the user's time.
    final problem = controller.inspect(bytes);
    if (problem != null) {
      _sayFailure(context, t, BackupFailure(problem));
      return;
    }

    BackupSnapshot? opened;
    CommyFailure? fatal;
    final unlocked = await BackupPasswordSheet.show(
      context,
      title: t.settings.backup.password.restoreTitle,
      confirm: false,
      submitLabel: t.settings.backup.password.open,
      onSubmit: (password) async {
        switch (await controller.read(bytes, password)) {
          case Ok(:final value):
            opened = value;
            return null;
          // Only a wrong password is worth another try in the sheet. A file
          // that opened and turned out damaged or too new would say the same
          // after every retry, each one a slow key derivation.
          case Err(
              failure: BackupFailure(problem: BackupProblem.wrongPassword)
            ):
            return t.error.backup.wrongPassword;
          case Err(:final failure):
            fatal = failure;
            return null;
        }
      },
    );
    final failed = fatal;
    if (failed != null && context.mounted) {
      _sayFailure(context, t, failed);
      return;
    }
    final snapshot = opened;
    if (!unlocked || snapshot == null || !context.mounted) {
      return;
    }

    final replace = await ConfirmSheet.show(
      context,
      title: t.settings.backup.restoreConfirm.title,
      body: t.settings.backup.restoreConfirm.body(
        date: _date(t, snapshot.createdAt.toLocal()),
        contents: _contents(t, snapshot),
      ),
      confirmLabel: t.settings.backup.restoreConfirm.confirm,
      cancelLabel: t.settings.backup.restoreConfirm.cancel,
      icon: CommyIcons.restore,
    );
    if (!replace || !context.mounted) {
      return;
    }

    // Taken now, while the section is surely on screen: the toast's action
    // may be tapped seconds later, from a screen this one is not part of.
    final router = GoRouter.maybeOf(context);
    final restored = await controller.restore(snapshot);
    if (!context.mounted) {
      return;
    }
    // Said in the language the flow started in. The restored settings may
    // name another, and the app switches to it a frame later — which is the
    // right moment to switch, and not a reason to guess at it here.
    final after = t;
    switch (restored) {
      case Ok(:final value):
        final lines = <String>[
          after.settings.backup.restored(contents: _contents(after, snapshot)),
          if (value.perAppDropped) after.settings.backup.perAppDropped,
          if (snapshot.skipped > 0)
            after.settings.backup.skipped(count: snapshot.skipped),
          if (value.missingRuleSets.isNotEmpty)
            after.settings.backup.ruleSetsMissing,
        ];
        ToastMessenger.show(
          context,
          message: lines.join('\n'),
          tone: CommyTone.connected,
          icon: CommyIcons.success,
          actionLabel: value.missingRuleSets.isEmpty || router == null
              ? null
              : after.settings.backup.ruleSetsAction,
          onAction: value.missingRuleSets.isEmpty || router == null
              ? null
              : () => router.go(AppRoutes.ruleSets),
        );
      case Err(:final failure):
        ToastMessenger.show(
          context,
          message: '${after.settings.backup.failed}: '
              '${FailureText.of(failure, after).message}',
          tone: CommyTone.error,
          icon: CommyIcons.warning,
        );
    }
  }

  static void _sayFailure(
    BuildContext context,
    Translations t,
    CommyFailure failure,
  ) {
    ToastMessenger.show(
      context,
      message: FailureText.of(failure, t).message,
      tone: CommyTone.error,
      icon: CommyIcons.warning,
    );
  }

  /// "2 subscriptions, 31 servers, 5 rules".
  static String _contents(Translations t, BackupSnapshot snapshot) => <String>[
        t.settings.backup.subscriptions(count: snapshot.subscriptions.length),
        // Servers, not rows: a panel's "App not supported" is stored as a
        // row and is not a server anyone can connect to.
        t.settings.backup.servers(
          count: PanelNotice.servers(snapshot.nodes).length,
        ),
        t.settings.backup.rules(count: snapshot.routing?.rules.length ?? 0),
      ].join(', ');

  /// The day a backup was made, the way this language writes dates.
  static String _date(Translations t, DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return switch (t.$meta.locale) {
      AppLocale.ru => '${two(at.day)}.${two(at.month)}.${at.year}',
      AppLocale.en => '${at.year}-${two(at.month)}-${two(at.day)}',
    };
  }
}
