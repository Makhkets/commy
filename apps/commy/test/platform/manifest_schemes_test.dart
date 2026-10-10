import 'dart:io';

import 'package:commy_config/commy_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// The schemes Android hands to Commy and the schemes Commy can read must be
/// the same list.
///
/// They live in two files in two languages, and each half is useless without
/// the other: a scheme only `ForeignImportLink` knows is never tapped through
/// to the app, and one only the manifest claims opens the import sheet on a
/// link it then calls unreadable — the exact failure the foreign links were
/// added to end (docs/06-data-model.md, "Импорт из других клиентов").
void main() {
  test('every foreign scheme the reader knows is claimed in the manifest', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final claimed = <String>{
      for (final match
          in RegExp('android:scheme="([^"]+)"').allMatches(manifest))
        match.group(1)!,
    };

    final missing = ForeignImportLink.schemes.difference(claimed);

    expect(missing, isEmpty, reason: 'Add these to the VIEW intent-filter.');
  });
}
