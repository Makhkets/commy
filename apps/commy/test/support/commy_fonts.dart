import 'dart:io';

import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/services.dart';

/// Puts the real typefaces into the engine.
///
/// Without this every glyph is the test framework's placeholder box, and a
/// picture of those proves nothing about a design whose type scale is half of
/// it. The faces live in `commy_ui`, so they are read off disk by path and
/// registered under both the bare family name and the package-qualified one
/// the type scale asks for — the same two-name trick
/// `packages/commy_ui/test/support/commy_test_host.dart` uses.
///
/// Call it from `setUpAll`, never from inside a `testWidgets` body: loading a
/// font is real, unfaked I/O, and a file read never completes inside the fake
/// async zone a widget test runs in.
Future<void> loadCommyFonts() async {
  if (_loaded) {
    return;
  }
  _loaded = true;

  const uiRoot = '../../packages/commy_ui/fonts';
  await _loadFamily(CommyFonts.ui, const <String>[
    '$uiRoot/Inter-Regular.ttf',
    '$uiRoot/Inter-Medium.ttf',
    '$uiRoot/Inter-SemiBold.ttf',
  ]);
  await _loadFamily(CommyFonts.mono, const <String>[
    '$uiRoot/JetBrainsMono-Regular.ttf',
    '$uiRoot/JetBrainsMono-Medium.ttf',
  ]);
  await _loadFamily('Lucide', const <String>['$uiRoot/Lucide.ttf']);
}

bool _loaded = false;

Future<void> _loadFamily(String family, List<String> paths) async {
  final loaders = <FontLoader>[
    FontLoader(family),
    FontLoader('packages/${CommyFonts.package}/$family'),
  ];
  for (final path in paths) {
    final bytes = await File(path).readAsBytes();
    for (final loader in loaders) {
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
  }
  for (final loader in loaders) {
    await loader.load();
  }
}
