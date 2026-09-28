import 'dart:convert';
import 'dart:typed_data';

import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/backup_snapshot.dart';
import 'package:commy_domain/src/entities/rule_set.dart';
import 'package:commy_domain/src/ports/backup_cipher.dart';
import 'package:commy_domain/src/ports/library_store.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/rule_set_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Gathers everything worth keeping and seals it under the user's password.
///
/// Returns the sealed bytes and the snapshot they hold — the second only so
/// the screen can say what was saved ("2 subscriptions, 31 servers"). The
/// plaintext never leaves this call: it is built in memory, sealed, and
/// dropped (rule R2). Where the bytes go is the caller's business; the only
/// honest answer is a file the user picks, never an upload (docs/06, "Экспорт").
class ExportBackupUseCase {
  /// Creates the use case.
  const ExportBackupUseCase({
    required this.library,
    required this.settings,
    required this.routing,
    required this.ruleSets,
    required this.cipher,
    required this.appVersion,
    required this.platform,
    this.now = DateTime.now,
  });

  /// The shortest password a backup is sealed under.
  ///
  /// The file may end up anywhere — a messenger, a USB stick — and whoever
  /// holds it can guess passwords offline for as long as they like. Argon2id
  /// makes each guess expensive; this makes the number of guesses large.
  static const int minPasswordLength = 8;

  /// Where subscriptions, groups and servers are read from — strictly: a
  /// credential that cannot be read fails the backup instead of leaving a
  /// server without it (LibraryStore.readLibrary).
  final LibraryStore library;

  /// Where the app's settings and the selected server are read from.
  final SettingsRepository settings;

  /// Where routing and DNS are read from.
  final RoutingRepository routing;

  /// Which rule sets are on disk — their tags go in, the files do not.
  final RuleSetRepository ruleSets;

  /// What seals the bytes.
  final BackupCipher cipher;

  /// The running Commy's version, written into the backup.
  final String appVersion;

  /// The platform this runs on (`android`, `ios`, …).
  final String platform;

  /// The clock the backup is dated by.
  final DateTime Function() now;

  /// Builds the backup and seals it under [password].
  Future<Result<({Uint8List bytes, BackupSnapshot snapshot}), CommyFailure>>
      call(String password) async {
    if (password.length < minPasswordLength) {
      return Err(
        UnknownFailure(
          ArgumentError.value(password.length, 'password', 'too short'),
          StackTrace.current,
        ),
      );
    }
    final BackupSnapshot taken;
    switch (await snapshot()) {
      case Ok(:final value):
        taken = value;
      case Err(:final failure):
        return Err(failure);
    }
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(taken.toJson())));
    final sealed = await cipher.seal(plain, password);
    // Best effort, and only for this buffer: the JSON string it was encoded
    // from stays on the heap until the collector takes it, and Dart has no
    // way to wipe a String. The promise that holds is R2's — none of it is
    // written to disk or to a log.
    plain.fillRange(0, plain.length, 0);
    return switch (sealed) {
      Ok(:final value) => Ok((bytes: value, snapshot: taken)),
      Err(:final failure) => Err(failure),
    };
  }

  /// Reads everything a backup holds, unsealed. Exposed for tests and for a
  /// preview; nothing in the app writes this value anywhere.
  Future<Result<BackupSnapshot, CommyFailure>> snapshot() async {
    final contents = await library.readLibrary();
    final settingsValue = await settings.read();
    final selected = await settings.readSelectedNodeId();
    final policy = await routing.read();
    final dns = await routing.readDns();
    final sets = await ruleSets.list();
    final failure = contents.failureOrNull ??
        settingsValue.failureOrNull ??
        selected.failureOrNull ??
        policy.failureOrNull ??
        dns.failureOrNull;
    final taken = contents.valueOrNull;
    if (failure != null || taken == null) {
      return Err(failure ?? const StorageFailure('library unreadable'));
    }
    return Ok(
      BackupSnapshot(
        createdAt: now().toUtc(),
        appVersion: appVersion,
        platform: platform,
        subscriptions: taken.subscriptions,
        groups: taken.groups,
        nodes: taken.nodes,
        routing: policy.valueOrNull,
        dns: dns.valueOrNull,
        settings: settingsValue.valueOrNull,
        selectedNodeId: selected.valueOrNull,
        // A rule-set directory that cannot be listed costs the backup a
        // reminder to download them again, not the backup itself.
        ruleSets: <String>[
          for (final set in sets.valueOrNull ?? const <RuleSet>[]) set.tag,
        ],
      ),
    );
  }
}
