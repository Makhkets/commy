import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// A server that failed its ping reads as grey: flag and name together.
///
/// It used to be one step lighter and nothing else, with the flag in full
/// colour, and on a phone that read as "the same row" — the owner could not
/// tell at a glance which servers were down.
void main() {
  Future<void> pumpTile(WidgetTester tester, {required bool reachable}) {
    return pumpCommy(
      tester,
      size: const Size(360, 120),
      child: NodeTile(
        name: 'Frankfurt 02',
        countryCode: 'DE',
        descriptors: const <String>['VLESS', 'Reality', 'TCP'],
        latency: reachable ? const Duration(milliseconds: 48) : null,
        isReachable: reachable,
        offlineSemanticLabel: 'offline',
        onTap: () {},
      ),
    );
  }

  testWidgets('an unreachable server gets a grey flag and a grey name',
      (tester) async {
    await pumpTile(tester, reachable: false);

    final filter = find.ancestor(
      of: find.byType(CountryFlag),
      matching: find.byType(ColorFiltered),
    );
    expect(filter, findsOneWidget);
    final colors = tester.element(find.byType(NodeTile)).colors;
    final name = tester.widget<Text>(find.text('Frankfurt 02'));
    expect(name.style?.color, colors.textTertiary);
    // Grey alone would be colour carrying a meaning: the glyph stays.
    expect(find.byIcon(CommyIcons.offline), findsOneWidget);
  });

  testWidgets('a server that answered keeps its colours', (tester) async {
    await pumpTile(tester, reachable: true);

    expect(
      find.ancestor(
        of: find.byType(CountryFlag),
        matching: find.byType(ColorFiltered),
      ),
      findsNothing,
    );
    final colors = tester.element(find.byType(NodeTile)).colors;
    final name = tester.widget<Text>(find.text('Frankfurt 02'));
    expect(name.style?.color, colors.textPrimary);
    expect(find.byIcon(CommyIcons.offline), findsNothing);
  });
}
