import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Proves that the light theme is a real theme and not a copy of the dark one.
///
/// A golden pair whose two files are byte-identical means the theme never
/// reached the widget — usually because something read a colour from a
/// constant instead of from `context.colors`. The pair still passes its own
/// golden test, twice, and proves nothing. This test is what catches it.
///
/// It also refuses to pass on an empty directory, so that a run which quietly
/// wrote no goldens at all cannot look like a green one.
void main() {
  test(
    'every golden differs between the two themes',
    tags: 'golden',
    // Reads the golden PNGs off disk, so it can only run where they exist —
    // and they exist only on Linux, which owns them because CI runs there.
    // See the note on `goldenTest` in test/support/commy_test_host.dart.
    skip: !Platform.isLinux,
    () {
    final directory = Directory('test/golden/goldens');
    expect(
      directory.existsSync(),
      isTrue,
      reason: 'Run `flutter test --update-goldens` first.',
    );

    final dark = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dark.png'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(
      dark,
      isNotEmpty,
      reason: 'No goldens on disk — nothing was actually photographed.',
    );

    final identical = <String>[];
    final orphaned = <String>[];
    for (final file in dark) {
      final light = File(file.path.replaceAll('.dark.png', '.light.png'));
      if (!light.existsSync()) {
        orphaned.add(file.uri.pathSegments.last);
        continue;
      }
      if (_sameBytes(file.readAsBytesSync(), light.readAsBytesSync())) {
        identical.add(file.uri.pathSegments.last);
      }
    }

    expect(orphaned, isEmpty, reason: 'Dark goldens with no light twin.');
    expect(
      identical,
      isEmpty,
      reason: 'These render the same in both themes, so the theme never '
          'applied and the golden proves nothing.',
    );
    },
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}
