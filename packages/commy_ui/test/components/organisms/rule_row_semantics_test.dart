import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// A rule that is off is still a row a tap opens — the tap is how it is
/// switched back on — so a screen reader must not announce it as disabled,
/// nor name it after its drag handle.
void main() {
  testWidgets('a rule that is off reads as "off", not as disabled',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCommy(
      tester,
      size: const Size(360, 120),
      child: ReorderableListView(
        buildDefaultDragHandles: false,
        onReorderItem: (_, __) {},
        children: <Widget>[
          RuleRow(
            key: const ValueKey<String>('r'),
            matcher: 'domain:example.com',
            actionLabel: 'DIRECT',
            action: RuleAction.direct,
            dragIndex: 0,
            dragHandleLabel: 'Drag rule',
            isEnabled: false,
            disabledLabel: 'off',
            onTap: () {},
          ),
        ],
      ),
    );

    final row = tester.getSemantics(
      find.descendant(
        of: find.byType(RuleRow),
        matching: find.byType(InkWell),
      ),
    );
    expect(row.value, 'off');
    expect(row.label, isNot(contains('Drag rule')));
    // The reorder is named as the row's hint, not as a node of its own.
    expect(row.hint, 'Drag rule');
    expect(find.bySemanticsLabel('Drag rule'), findsNothing);
    expect(
      row,
      isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
    );
    handle.dispose();
  });
}
