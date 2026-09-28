import 'dart:typed_data';

import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';

/// Seals bytes under a password the user chose, and opens them again.
///
/// A backup holds every credential the user owns, so it never exists on disk
/// in the clear: it is sealed in memory and only the sealed bytes are handed
/// to the file dialog (rule R2). The password is not stored anywhere — lose
/// it and the backup is lost, which the export screen says out loud.
///
/// Failures are [BackupFailure]s, except a [StorageFailure] if the platform
/// refuses the work outright.
abstract interface class BackupCipher {
  /// Seals [plain] under [password].
  Future<Result<Uint8List, CommyFailure>> seal(
    Uint8List plain,
    String password,
  );

  /// Opens what [seal] produced. A wrong password and a changed file are the
  /// same answer, `BackupProblem.wrongPassword`: authenticated encryption
  /// cannot tell them apart.
  Future<Result<Uint8List, CommyFailure>> open(
    Uint8List sealed,
    String password,
  );

  /// Checks what can be checked without the password: is this a backup at
  /// all, and one this version can open. Null when it is worth asking for the
  /// password. Cheap — no key derivation — so a wrong file is turned away
  /// before the user types anything.
  BackupProblem? inspect(Uint8List sealed);
}
