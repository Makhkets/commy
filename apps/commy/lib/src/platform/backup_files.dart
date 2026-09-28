import 'dart:typed_data';

import 'package:commy_domain/commy_domain.dart';

/// Where a backup file comes from and goes to: a file the user picks.
///
/// Never a share sheet and never an upload. The share sheet's first targets
/// are messengers and cloud drives, and "never to the cloud" is a promise of
/// the product (docs/06-data-model.md, "Экспорт"): the system's own save
/// dialog puts the file where the user says, and nowhere else. The file is
/// sealed before it gets here, so even a user who then sends it somewhere
/// sends ciphertext.
///
/// A port rather than static calls on `FilePicker`, so the flows around it can
/// be tested with a fake.
abstract interface class BackupFiles {
  /// Offers [bytes] to be saved as [fileName]. Ok(true) when saved, Ok(false)
  /// when the user closed the dialog.
  Future<Result<bool, CommyFailure>> save({
    required String fileName,
    required Uint8List bytes,
    required String dialogTitle,
  });

  /// Lets the user pick a file. Its bytes, or Ok(null) when nothing was picked.
  Future<Result<Uint8List?, CommyFailure>> pick();
}
