import 'dart:io';
import 'dart:typed_data';

import 'package:commy/src/platform/backup_files.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:file_picker/file_picker.dart';

/// [BackupFiles] on the system's own dialogs, through `file_picker`.
///
/// On Android both are the Storage Access Framework: "create document" to
/// save, which writes the bytes straight to where the user chose with no
/// copy of our own left behind, and "open document" to pick.
class FilePickerBackupFiles implements BackupFiles {
  /// Creates the adapter.
  const FilePickerBackupFiles();

  @override
  Future<Result<bool, CommyFailure>> save({
    required String fileName,
    required Uint8List bytes,
    required String dialogTitle,
  }) async {
    try {
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        dialogTitle: dialogTitle,
      );
      return Ok(saved != null);
    } on Object catch (error, stackTrace) {
      return Err(UnknownFailure(error, stackTrace));
    }
  }

  @override
  Future<Result<Uint8List?, CommyFailure>> pick() async {
    try {
      // Any type: the picker filters by MIME type, and there is none for our
      // extension — a filter would hide the very file the user saved. What
      // the file is, the cipher decides from its first bytes.
      final picked = await FilePicker.pickFile();
      final path = picked?.path;
      if (picked == null || path == null) {
        return const Ok(null);
      }
      try {
        final file = File(path);
        // Measured before it is read: a video picked by mistake is not a
        // backup, and reading it whole to find out would be the slow way.
        if (await file.length() > maxBytes) {
          return const Err(BackupFailure(BackupProblem.notABackup));
        }
        return Ok(await file.readAsBytes());
      } finally {
        // On Android the picker hands over a copy in our cache directory.
        // It is ciphertext, but a copy nobody needs is a copy to delete.
        await FilePicker.clearTemporaryFiles();
      }
    } on Object catch (error, stackTrace) {
      return Err(UnknownFailure(error, stackTrace));
    }
  }

  /// Anything larger is not a backup this app made.
  static const int maxBytes = PasswordBackupCipher.maxFileBytes;
}
