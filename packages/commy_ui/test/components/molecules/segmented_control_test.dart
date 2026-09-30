import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// Which segment is chosen has to be visible without telling two greys
/// apart.
///
/// The chosen segment was only a `bg/overlay` fill on the `bg/inset` track —
/// 1.07:1 in the light theme — with a label one step darker; in daylight the
/// routing screen's Global, Rules and Direct looked the same.
void main() {
  Color? outlineOf(WidgetTester tester, String label) {
    final segment = tester.widget<Container>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first,
    );
    final decoration = segment.foregroundDecoration as BoxDecoration?;
    return (decoration?.border as Border?)?.top.color;
  }

  for (final theme in CommyGoldenTheme.values) {
    testWidgets(
        'the chosen segment is outlined, the others are not · '
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

      expect(outlineOf(tester, 'Правила'), colors.borderStrong);
      expect(outlineOf(tester, 'Глобально'), CommyColors.transparent);
      expect(outlineOf(tester, 'Прямо'), CommyColors.transparent);
    });
  }
}
