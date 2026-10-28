import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// Which segment is chosen has to be visible without telling two greys
/// apart.
///
/// The chosen segment was once only a fill one step off the track — 1.07:1
/// in the light theme — and in daylight the routing screen's Global, Rules
/// and Direct looked the same. Now one thumb travels under the chosen label,
/// and its edge is `line-strong`: 3:1 against the track in both themes.
void main() {
  BoxDecoration thumbOf(WidgetTester tester) {
    final positioned = tester.widget<AnimatedPositioned>(
      find.byType(AnimatedPositioned),
    );
    return (positioned.child as DecoratedBox).decoration as BoxDecoration;
  }

  Rect thumbRect(WidgetTester tester) =>
      tester.getRect(find.byType(AnimatedPositioned));

  for (final theme in CommyGoldenTheme.values) {
    testWidgets(
        'the chosen segment sits on the one outlined thumb · '
        '${theme.name}', (tester) async {
      await pumpCommy(
        tester,
        theme: theme,
        child: SegmentedControl<String>(
          value: 'rules',
          onChanged: (_) {},
          segments: const <SegmentedControlItem<String>>[
            SegmentedControlItem<String>(value: 'global', label: 'Глобально'),
            SegmentedControlItem<String>(value: 'rules', label: 'Правила'),
            SegmentedControlItem<String>(value: 'direct', label: 'Прямо'),
          ],
        ),
      );
      final colors = theme.data.extension<CommyColors>()!;

      final edge = (thumbOf(tester).border! as Border).top.color;
      expect(edge, colors.borderStrong);
      // One thumb, and it sits under the chosen label.
      expect(find.byType(AnimatedPositioned), findsOneWidget);
      expect(
        thumbRect(tester).contains(tester.getCenter(find.text('Правила'))),
        isTrue,
      );
      expect(
        thumbRect(tester).contains(tester.getCenter(find.text('Прямо'))),
        isFalse,
      );
    });
  }
}
