import 'dart:convert';
import 'dart:typed_data';

import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/backup_snapshot.dart';
import 'package:commy_domain/src/ports/backup_cipher.dart';

/// Opens a backup file and reads what is inside, without changing anything.
///
/// The first half of a restore. The user sees what the file holds — how many
/// subscriptions and servers, from when — before anything on the phone is
/// replaced; `RestoreBackupUseCase` is the second half, after they agree.
class ReadBackupUseCase {
  /// Creates the use case.
  const ReadBackupUseCase({required this.cipher});

  /// What opens the bytes.
  final BackupCipher cipher;

  /// Opens [sealed] with [password] and parses the snapshot inside.
  Future<Result<BackupSnapshot, CommyFailure>> call(
    Uint8List sealed,
    String password,
  ) async {
    final Uint8List plain;
    switch (await cipher.open(sealed, password)) {
      case Ok(:final value):
        plain = value;
      case Err(:final failure):
        return Err(failure);
    }
    try {
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) {
        return const Err(BackupFailure(BackupProblem.unreadable));
      }
      final json = decoded.cast<String, Object?>();
      final schema = BackupSnapshot.schemaOf(json);
      if (schema == null) {
        return const Err(BackupFailure(BackupProblem.unreadable));
      }
      if (schema > BackupSnapshot.schema) {
        return const Err(BackupFailure(BackupProblem.newerVersion));
      }
      return Ok(BackupSnapshot.fromJson(json));
    } on FormatException {
      // Authenticated and still not JSON, or JSON and not a snapshot: made by
      // something that is not Commy, with the right key. Nothing to restore.
      return const Err(BackupFailure(BackupProblem.unreadable));
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }
}
