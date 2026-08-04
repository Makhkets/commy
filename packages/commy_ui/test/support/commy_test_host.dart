import 'dart:io';

import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The harness every test in this package renders through.
///
/// Three things are settled here once, so that no individual test has to think
/// about them:
///
/// * **Fonts.** A golden taken against the test framework's placeholder font
///   proves nothing about a design system whose type scale is half the design.
///   [loadCommyFonts] puts the real Inter, JetBrains Mono and Lucide into the
///   engine before anything is pumped.
/// * **Both themes.** Every golden is taken twice. Dark is the theme the
///   product was designed in; light is a full derivation and gets caught here
///   when it stops being one.
/// * **Stillness.** Animations are disabled, the device pixel ratio is 1 and
///   the surface is exactly the size asked for, so a golden differs only when
///   the widget does.

/// The key of the frame each golden photographs.
const ValueKey<String> goldenFrame = ValueKey<String>('commy-golden-frame');

/// The two themes every golden is taken in.
enum CommyGoldenTheme {
  /// The theme the product was designed in.
  dark,

  /// The full derivation of it.
  light;

  /// The [ThemeData] this theme renders through.
  ThemeData get data =>
      this == CommyGoldenTheme.dark ? CommyTheme.dark : CommyTheme.light;
}

bool _fontsLoaded = false;

/// Loads the vendored typefaces and the Lucide icon font into the engine.
///
/// Called from [useCommyGoldens] rather than from inside a test: font loading
/// is real, unfaked I/O, and `testWidgets` runs its body inside a fake async
/// zone where a file read never completes.
Future<void> loadCommyFonts() async {
  if (_fontsLoaded) {
    return;
  }
  _fontsLoaded = true;

  // Our own faces are read straight off disk. They are declared in the
  // pubspec, but the asset key a package's own fonts get differs between
  // running the package's tests and running an app that depends on it — the
  // path never does.
  await _loadFamily(CommyFonts.ui, const <String>[
    'fonts/Inter-Regular.ttf',
    'fonts/Inter-Medium.ttf',
    'fonts/Inter-SemiBold.ttf',
  ]);
  await _loadFamily(CommyFonts.mono, const <String>[
    'fonts/JetBrainsMono-Regular.ttf',
    'fonts/JetBrainsMono-Medium.ttf',
  ]);

  // Lucide lives in another package, so it can only be reached through the
  // asset bundle the test runner assembled.
  const lucide = 'packages/lucide_icons_flutter/assets/lucide.ttf';
  final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(rootBundle.load(lucide));
  await icons.load();
}

Future<void> _loadFamily(String family, List<String> paths) async {
  // Both the bare name and the package-qualified one: the type scale asks for
  // the qualified form, and anything that reaches for the bare one still gets
  // the same face instead of silently falling back.
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

/// Call once at the top of a golden test's `main()`.
void useCommyGoldens() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadCommyFonts);
}

/// Renders [child] on a surface of exactly [size], in [theme], with animations
/// off.
Future<void> pumpCommy(
  WidgetTester tester, {
  required Widget child,
  CommyGoldenTheme theme = CommyGoldenTheme.dark,
  Size size = const Size(360, 160),
  double textScale = 1,
  bool disableAnimations = true,
  bool frame = true,
  EdgeInsets? padding,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final data = theme.data;
  Widget content = ColoredBox(
    color: data.scaffoldBackgroundColor,
    // A transparent Material, because several Material widgets we wrap — the
    // text field above all — assert on having one somewhere above them. It
    // paints nothing, so it cannot show up in a golden.
    child: Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: padding ?? EdgeInsets.all(CommySpacing.standard.s4),
          child: child,
        ),
      ),
    ),
  );
  if (frame) {
    content = RepaintBoundary(key: goldenFrame, child: content);
  }

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: data,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: content,
      ),
    ),
  );
  await tester.pump();
}

/// Registers one golden test per theme for [name].
///
/// [builder] is a function rather than a widget so that each theme gets a
/// freshly built tree — a widget instance reused across two pumps would keep
/// the state of the first.
void goldenTest(
  String name, {
  required WidgetBuilder builder,
  required Size size,
  double textScale = 1,
  EdgeInsets? padding,
}) {
  for (final theme in CommyGoldenTheme.values) {
    testWidgets(
      '$name · ${theme.name}',
      (tester) async {
        await pumpCommy(
          tester,
          theme: theme,
          size: size,
          textScale: textScale,
          padding: padding,
          child: Builder(builder: builder),
        );
        await expectLater(
          find.byKey(goldenFrame),
          matchesGoldenFile('goldens/$name.${theme.name}.png'),
        );
      },
      tags: 'golden',
    );
  }
}

/// Renders [child] at [textScale] on a phone-sized surface, without a frame.
///
/// The one thing this is for is catching overflow: a `Column` that fits at
/// 100 % and runs 87 dp off the bottom at 200 % is the single most common way
/// a screen stops working for the people who need it most. Callers assert on
/// `tester.takeException()`.
Future<void> pumpAtTextScale(
  WidgetTester tester, {
  required Widget child,
  double textScale = 2,
  Size size = const Size(320, 720),
  CommyGoldenTheme theme = CommyGoldenTheme.dark,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  await pumpCommy(
    tester,
    theme: theme,
    size: size,
    textScale: textScale,
    padding: padding,
    frame: false,
    child: child,
  );
}
