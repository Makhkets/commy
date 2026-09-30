import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// What a collapsed subscription card still shows.
///
/// The rows that say what the card is doing — a measurement in progress and
/// its Cancel, the notice a panel sends instead of servers — used to be the
/// first of its server rows and folded away with them. "Measure all" on a
/// collapsed card then ran with no progress and no way to stop it.
void main() {
  Future<void> pumpCard(WidgetTester tester, {required bool collapsed}) {
    return pumpCommy(
      tester,
      size: const Size(390, 400),
      child: SubscriptionCard(
        name: 'MAKHKETS VPN',
        refreshLabel: 'Обновить',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        isCollapsed: collapsed,
        status: const <Widget>[Text('Замеряю 8 из 24')],
        nodes: <Widget>[
          NodeTile(name: 'Amsterdam 03', countryCode: 'NL', onTap: () {}),
          NodeTile(name: 'Frankfurt 01', countryCode: 'DE', onTap: () {}),
        ],
      ),
    );
  }

  testWidgets('a collapsed card folds its servers and keeps its status',
      (tester) async {
    await pumpCard(tester, collapsed: true);

    expect(find.text('Замеряю 8 из 24'), findsOneWidget);
    expect(find.byType(NodeTile), findsNothing);
    expect(find.byType(CommyDivider), findsNothing);
  });

  testWidgets('an open card shows its status above its servers',
      (tester) async {
    await pumpCard(tester, collapsed: false);

    expect(find.byType(NodeTile), findsNWidgets(2));
    expect(find.byType(CommyDivider), findsNWidgets(2));
    final status = tester.getTopLeft(find.text('Замеряю 8 из 24')).dy;
    final first = tester.getTopLeft(find.text('Amsterdam 03')).dy;
    expect(status, lessThan(first));
  });

  testWidgets("the panel's notice is drawn in the secondary step",
      (tester) async {
    // It is 11 px, and text/tertiary is for 13 px and up: on the group
    // header it made 4.43:1 in the light theme, under AA.
    const note = 'По вопросам пишите в поддержку: @support';
    await pumpCommy(
      tester,
      theme: CommyGoldenTheme.light,
      size: const Size(390, 400),
      child: const SubscriptionCard(
        name: 'MAKHKETS VPN',
        refreshLabel: 'Обновить',
        pingAllLabel: 'Измерить все',
        moreLabel: 'Ещё',
        announcement: note,
      ),
    );

    expect(
      tester.widget<Text>(find.text(note)).style?.color,
      CommyColors.light.textSecondary,
    );
  });
}
