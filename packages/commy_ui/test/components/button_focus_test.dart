import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

/// A button that has keyboard focus looks like it.
///
/// Focus used to be the InkWell's: a 12% overlay of white on the dark theme
/// and of black on the light one. On the primary fill — a near-white, a
/// near-black — that moved by 1.02:1, and the compact variant paints its fill
/// above the overlay, so a keyboard user tabbing onto "Add" saw nothing
/// change at all.
void main() {
  Color? ringOf(WidgetTester tester, String label) {
    final pill = tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    final decoration = pill.foregroundDecoration as BoxDecoration?;
    return (decoration?.border as Border?)?.top.color;
  }

  for (final compact in <bool>[false, true]) {
    for (final theme in CommyGoldenTheme.values) {
      testWidgets(
          'a ${compact ? 'compact' : 'regular'} primary button draws a ring '
          'when a key focuses it · ${theme.name}', (tester) async {
        await pumpCommy(
          tester,
          theme: theme,
          child: CommyButton(
            label: 'Добавить',
            onPressed: () {},
            isCompact: compact,
          ),
        );
        final colors = theme.data.extension<CommyColors>()!;
        expect(ringOf(tester, 'Добавить'), CommyColors.transparent);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(ringOf(tester, 'Добавить'), colors.borderStrong);
      });
    }
  }

  testWidgets('a tap does not draw the ring', (tester) async {
    await pumpCommy(
      tester,
      child: CommyButton(label: 'Добавить', onPressed: () {}),
    );

    await tester.tap(find.text('Добавить'));
    await tester.pump();

    expect(ringOf(tester, 'Добавить'), CommyColors.transparent);
  });

  testWidgets('each button is one stop for Tab and works with Space',
      (tester) async {
    final pressed = <String>[];
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyButton(label: 'Первая', onPressed: () => pressed.add('1')),
          CommyButton(
            label: 'Вторая',
            onPressed: () => pressed.add('2'),
            isCompact: true,
          ),
        ],
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(pressed, <String>['2', '2']);
  });
}
