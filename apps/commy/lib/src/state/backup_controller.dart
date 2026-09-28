import 'dart:typed_data';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saving and restoring a backup (G10): the steps, each its own call, so the
/// screen can put a question between any two of them.
///
/// The state is only "is something running" — the button spinner. What each
/// step found is its return value: the screen says it right away, in a toast
/// or under a password field, and nothing needs to remember it afterwards.
///
/// Nothing here logs: a backup is every credential the user has (R2, R3).
final backupControllerProvider = NotifierProvider<BackupController, bool>(
  BackupController.new,
);

/// See [backupControllerProvider].
class BackupController extends Notifier<bool> {
  /// A flow — sheets, dialogs, the work between them — is under way. Not the
  /// state: nothing on screen changes for it, it only turns a second tap
  /// away before the first one's sheet has even appeared.
  bool _inFlow = false;

  @override
  bool build() => false;

  /// Starts a flow, unless one is already running. Pair with [endFlow].
  bool beginFlow() {
    if (_inFlow) {
      return false;
    }
    _inFlow = true;
    return true;
  }

  /// Ends the flow [beginFlow] started.
  void endFlow() => _inFlow = false;

  /// Builds the backup and seals it under [password]. Seconds, not
  /// milliseconds: the key derivation is made to be slow (ADR-0017).
  Future<Result<({Uint8List bytes, BackupSnapshot snapshot}), CommyFailure>>
      seal(String password) =>
          _busy(() => ref.read(exportBackupUseCaseProvider)(password));

  /// Offers the sealed [bytes] to the system's save dialog, named after the
  /// day the backup was [madeAt].
  Future<Result<bool, CommyFailure>> save(
    Uint8List bytes, {
    required DateTime madeAt,
    required String dialogTitle,
  }) {
    return ref.read(backupFilesProvider).save(
          fileName: fileNameFor(madeAt.toLocal()),
          bytes: bytes,
          dialogTitle: dialogTitle,
        );
  }

  /// Lets the user pick a backup file.
  Future<Result<Uint8List?, CommyFailure>> pick() =>
      ref.read(backupFilesProvider).pick();

  /// Whether [bytes] is worth asking a password for; the problem if not.
  BackupProblem? inspect(Uint8List bytes) =>
      ref.read(backupCipherProvider).inspect(bytes);

  /// Opens [bytes] with [password]. Changes nothing.
  Future<Result<BackupSnapshot, CommyFailure>> read(
    Uint8List bytes,
    String password,
  ) =>
      _busy(() => ref.read(readBackupUseCaseProvider)(bytes, password));

  /// Replaces what this phone has with [snapshot].
  ///
  /// The tunnel goes down first: the restore replaces the server it runs on,
  /// and the live reload that follows every settings change would otherwise
  /// build configs from a library that is half old, half new. Under the
  /// system kill switch "down" is the blocking interface, so nothing leaks
  /// while this runs (ADR-0016). It does not come back up by itself — the
  /// user reconnects to the restored servers when they choose to.
  Future<
      Result<({List<String> missingRuleSets, bool perAppDropped}),
          CommyFailure>> restore(BackupSnapshot snapshot) {
    return _busy(() async {
      await _tunnelDown();
      final result = await ref.read(restoreBackupUseCaseProvider)(snapshot);
      // Read once and kept, so read again — after a failure too: the library
      // is the first thing replaced, and the selection went with it.
      ref.invalidate(selectedNodeIdProvider);
      if (result.isOk) {
        final settings = snapshot.settings;
        if (settings != null) {
          // The receiver's switch lives in the package manager, which a
          // restore does not reach any other way.
          await ref
              .read(systemSettingsProvider)
              .setStartOnBoot(enabled: settings.startOnBoot);
        }
      }
      return result;
    });
  }

  /// Takes the tunnel down and waits until it is. A connect already under
  /// way is let finish first — `disconnect` declines while one runs — and is
  /// then taken down with the rest.
  Future<void> _tunnelDown() async {
    final tunnel = ref.read(tunnelControllerProvider.notifier);
    for (var waited = Duration.zero;
        ref.read(tunnelControllerProvider).isBusy && waited < _connectWait;
        waited += _poll) {
      await Future<void>.delayed(_poll);
    }
    final status = ref.read(coreStatusProvider).value;
    if (status != null && status is! TunnelIdle) {
      await tunnel.disconnect();
    }
  }

  static const Duration _poll = Duration(milliseconds: 100);
  static const Duration _connectWait = Duration(seconds: 30);

  /// `commy-2026-09-29.commybackup`: the date, so two backups do not share a
  /// name, and nothing about the user, so the name gives nothing away.
  static String fileNameFor(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'commy-${now.year}-${two(now.month)}-${two(now.day)}.commybackup';
  }

  Future<T> _busy<T>(Future<T> Function() work) async {
    state = true;
    try {
      return await work();
    } finally {
      if (ref.mounted) {
        state = false;
      }
    }
  }
}
