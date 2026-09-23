import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/commy_test_host.dart';

/// An unlimited plan draws the whole track, in the calm colour.
///
/// The owner asked for a full bar — "as if it were all spent, except it is
/// not, because there is no end". Full, but never red: a full red bar is the
/// one thing that has to mean "spent".
void main() {
  Future<Color?> fillOf(WidgetTester tester, QuotaBar bar) async {
    await pumpCommy(tester, size: const Size(360, 80), child: bar);
    final fill = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(QuotaBar),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return (fill.decoration as BoxDecoration?)?.color ??
        tester
            .widget<ColoredBox>(
              find.descendant(
                of: find.byWidget(fill),
                matching: find.byType(ColoredBox),
              ),
            )
            .color;
  }

  testWidgets('unlimited fills the track in the calm colour', (tester) async {
    const bar = QuotaBar(ratio: 0, isUnlimited: true);
    final fill = await fillOf(tester, bar);
    final colors = tester.element(find.byType(QuotaBar)).colors;

    expect(bar.clampedRatio, 1);
    expect(
      tester
          .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
          .widthFactor,
      1,
    );
    expect(fill, colors.accentSolid);
    expect(fill, isNot(colors.statusError));
  });

  testWidgets('a quota that is nearly gone is still red', (tester) async {
    final fill = await fillOf(tester, const QuotaBar(ratio: 0.97));
    final colors = tester.element(find.byType(QuotaBar)).colors;

    expect(fill, colors.statusError);
  });
}
