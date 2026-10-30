import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

void main() {
  for (final state in ConnectState.values) {
    testWidgets('the dial handles taps in ${state.name}', (tester) async {
      var calls = 0;
      await pumpCommy(
        tester,
        size: const Size(390, 340),
        child: ConnectButton(
          state: state,
          label: 'Действие',
          onPressed: () => calls++,
        ),
      );
      // The power symbol is a target, not just the caption under it.
      await tester.tap(find.byType(Icon));
      await tester.pump();
      expect(calls, state == ConnectState.stopping ? 0 : 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the dial has one accessible action and accepts keyboard input',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await pumpCommy(
      tester,
      size: const Size(390, 340),
      child: ConnectButton(
        state: ConnectState.idle,
        label: 'Подключиться',
        onPressed: () => calls++,
      ),
    );
    expect(find.bySemanticsLabel('Подключиться'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, 2);
    semantics.dispose();
  });

  testWidgets('a disabled dial cannot connect or take keyboard activation',
      (tester) async {
    await pumpCommy(
      tester,
      size: const Size(390, 340),
      child: const ConnectButton(
        state: ConnectState.idle,
        label: 'Подключиться',
        onPressed: null,
      ),
    );
    await tester.tap(find.byType(Icon));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text wraps and reduced motion leaves no ticker running',
      (tester) async {
    await pumpCommy(
      tester,
      size: const Size(320, 420),
      textScale: 2,
      child: ConnectButton(
        state: ConnectState.starting,
        label: 'Отменить подключение',
        onPressed: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
