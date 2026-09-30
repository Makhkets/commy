import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// The action word in a toast and in a banner is a button a thumb can hit.
///
/// It was the word alone under a `GestureDetector`: a 22 pt strip, no button
/// role, no focus. The toast's "Вернуть" is the only undo for a routing rule
/// deleted with a swipe and lasts six seconds; the banner's action is the
/// way out of a failed connection.
void main() {
  Future<void> expectAButton(
    WidgetTester tester, {
    required String word,
    required int Function() taken,
  }) async {
    expect(tester, meetsGuideline(androidTapTargetGuideline));
    expect(
      tester.getSemantics(find.text(word)),
      isSemantics(isButton: true, hasTapAction: true, label: word),
    );

    // A thumb that lands ten points under the word still takes it.
    final before = taken();
    await tester.tapAt(
      tester.getRect(find.text(word)).bottomCenter + const Offset(0, 10),
    );
    await tester.pump();
    expect(taken(), before + 1);

    // And so does a keyboard.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taken(), before + 2);
  }

  testWidgets("a toast's undo is a 48 pt button", (tester) async {
    final handle = tester.ensureSemantics();
    var undone = 0;
    await pumpCommy(
      tester,
      child: Toast(
        message: 'Правило удалено',
        actionLabel: 'Вернуть',
        onAction: () => undone++,
      ),
    );

    await expectAButton(tester, word: 'Вернуть', taken: () => undone);
    handle.dispose();
  });

  testWidgets("a banner's action is a 48 pt button", (tester) async {
    final handle = tester.ensureSemantics();
    var retried = 0;
    await pumpCommy(
      tester,
      size: const Size(360, 240),
      child: ErrorBanner(
        title: 'Не удалось подключиться',
        message: 'Сервер не ответил за 10 секунд.',
        actionLabel: 'Повторить',
        onAction: () => retried++,
      ),
    );

    await expectAButton(tester, word: 'Повторить', taken: () => retried);
    handle.dispose();
  });
}
