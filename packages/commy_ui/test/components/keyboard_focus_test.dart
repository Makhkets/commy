import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

/// Every control can be reached with Tab and worked with Space or Enter.
///
/// The switch, the checkbox, the radio, the segments, the chip's cross and
/// the panel notice were a `GestureDetector` and a painting, with no focus
/// node: Tab went past every one of them. With a keyboard, a D-pad or a
/// Chromebook, auto-connect could not be turned on and the routing mode
/// could not be changed.
void main() {
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  Future<void> tab(WidgetTester tester, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await press(tester, LogicalKeyboardKey.tab);
    }
  }

  testWidgets('a switch is reached with Tab and flipped with Space',
      (tester) async {
    final flips = <bool>[];
    await pumpCommy(
      tester,
      child: CommySwitch(value: false, onChanged: flips.add),
    );

    await tab(tester);
    await press(tester, LogicalKeyboardKey.space);

    expect(flips, <bool>[true]);
  });

  testWidgets('a switch flips with Enter as well', (tester) async {
    final flips = <bool>[];
    await pumpCommy(
      tester,
      child: CommySwitch(value: true, onChanged: flips.add),
    );

    await tab(tester);
    await press(tester, LogicalKeyboardKey.enter);

    expect(flips, <bool>[false]);
  });

  testWidgets('a disabled switch is passed over', (tester) async {
    var before = 0;
    var after = 0;
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyButton(label: 'До', onPressed: () => before++),
          const CommySwitch(value: false, onChanged: null),
          CommyButton(label: 'После', onPressed: () => after++),
        ],
      ),
    );

    await tab(tester, 2);
    await press(tester, LogicalKeyboardKey.space);

    expect((before, after), (0, 1));
  });

  testWidgets('a segment is reached with Tab and chosen with Enter',
      (tester) async {
    final chosen = <String>[];
    await pumpCommy(
      tester,
      child: SegmentedControl<String>(
        value: 'rules',
        onChanged: chosen.add,
        segments: const <SegmentedControlItem<String>>[
          SegmentedControlItem<String>(value: 'global', label: 'Глобально'),
          SegmentedControlItem<String>(value: 'rules', label: 'Правила'),
          SegmentedControlItem<String>(value: 'direct', label: 'Прямо'),
        ],
      ),
    );

    await tab(tester, 3);
    await press(tester, LogicalKeyboardKey.enter);

    expect(chosen, <String>['direct']);
  });

  testWidgets('a checkbox is reached with Tab and ticked with Space',
      (tester) async {
    final ticks = <bool>[];
    await pumpCommy(
      tester,
      child: CommyCheckbox(value: false, onChanged: ticks.add),
    );

    await tab(tester);
    await press(tester, LogicalKeyboardKey.space);

    expect(ticks, <bool>[true]);
  });

  testWidgets('a radio is reached with Tab and chosen with Space',
      (tester) async {
    final chosen = <int>[];
    await pumpCommy(
      tester,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyRadio<int>(value: 1, groupValue: 1, onChanged: chosen.add),
          CommyRadio<int>(value: 2, groupValue: 1, onChanged: chosen.add),
        ],
      ),
    );

    await tab(tester, 2);
    await press(tester, LogicalKeyboardKey.space);

    expect(chosen, <int>[2]);
  });

  testWidgets("a chip's cross is reached after the chip itself",
      (tester) async {
    var taps = 0;
    var removals = 0;
    await pumpCommy(
      tester,
      child: CommyChip(
        label: 'Быстрые',
        onTap: () => taps++,
        onRemove: () => removals++,
        removeSemanticLabel: 'Убрать фильтр',
      ),
    );

    await tab(tester, 2);
    await press(tester, LogicalKeyboardKey.space);

    expect((taps, removals), (0, 1));
  });

  testWidgets("the panel's notice opens from the keyboard", (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCommy(
      tester,
      size: const Size(390, 400),
      child: const SubscriptionCard(
        name: 'MAKHKETS VPN',
        refreshLabel: 'Обновить',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        announcement: 'Сегодня с 23:00 до 01:00 плановые работы на серверах '
            'в Нидерландах. Пользуйтесь Германией или Финляндией, а по '
            'вопросам пишите в поддержку.',
      ),
    );
    final notice = find.textContaining('плановые работы');
    expect(
      tester.getSemantics(notice),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: false),
    );

    // Refresh, measure all, more — then the notice.
    await tab(tester, 4);
    await press(tester, LogicalKeyboardKey.enter);

    expect(
      tester.getSemantics(notice),
      isSemantics(isButton: true, hasExpandedState: true, isExpanded: true),
    );
    handle.dispose();
  });
}
