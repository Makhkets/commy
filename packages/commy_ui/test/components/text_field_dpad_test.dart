import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

/// A D-pad reaches what is below a one-line field. Up and down used to stop
/// in it, so on a remote the switch and the Save button of a sheet with a
/// field at the top could not be reached at all.
void main() {
  Future<FocusNode> pumpForm(WidgetTester tester, {int? maxLines = 1}) async {
    final below = FocusNode(debugLabel: 'below');
    addTearDown(below.dispose);
    await pumpCommy(
      tester,
      size: const Size(360, 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CommyTextField(
            labelText: 'Match',
            autofocus: true,
            maxLines: maxLines,
          ),
          const SizedBox(height: 16),
          TextButton(
            focusNode: below,
            onPressed: () {},
            child: const Text('Save'),
          ),
        ],
      ),
    );
    await tester.pump();
    return below;
  }

  testWidgets('arrow down leaves a one-line field', (tester) async {
    final below = await pumpForm(tester);
    expect(below.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(below.hasFocus, isTrue);
  });

  // Android's own fields: the first press takes the caret to the edge, the
  // next one leaves.
  testWidgets('a caret inside the text moves to the edge first',
      (tester) async {
    final below = await pumpForm(tester);
    await tester.enterText(find.byType(EditableText), 'domain:example.com');
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText))
      ..userUpdateTextEditingValue(
        const TextEditingValue(
          text: 'domain:example.com',
          selection: TextSelection.collapsed(offset: 3),
        ),
        SelectionChangedCause.keyboard,
      );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(below.hasFocus, isFalse);
    expect(editable.textEditingValue.selection.extentOffset, 18);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(below.hasFocus, isTrue);
  });

  testWidgets('a multi-line field leaves after its last line', (tester) async {
    final below = await pumpForm(tester, maxLines: 4);
    await tester.enterText(find.byType(EditableText), 'one\ntwo');
    await tester.pump();
    tester
        .state<EditableTextState>(find.byType(EditableText))
        .userUpdateTextEditingValue(
          const TextEditingValue(
            text: 'one\ntwo',
            selection: TextSelection.collapsed(offset: 0),
          ),
          SelectionChangedCause.keyboard,
        );
    await tester.pump();

    // First line → second line → end of the text → out.
    for (var press = 0; press < 2; press++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(below.hasFocus, isFalse, reason: 'press $press');
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(below.hasFocus, isTrue);
  });
}
