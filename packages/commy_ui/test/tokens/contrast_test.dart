import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The third text step and the idle tone clear WCAG AA on every ground they
/// are drawn on, not only on `bg/surface`.
///
/// The contrast table in docs/04-design-system.md checked them against the
/// surface alone, where the light #6C7178 made 4.9:1. The grounds they
/// actually sit on are greyer or tinted, and there it fell short: 4.35:1 in
/// the ПРЯМО badge on its own idle wash, 4.43:1 for every text field hint on
/// `bg/overlay`, 4.25:1 for the name of the active server when it stops
/// answering (on the connected wash) — and 4.45:1 for that same row in the
/// dark theme.
void main() {
  /// WCAG 2.1 contrast of [foreground] drawn over [ground], which may be a
  /// wash with its own alpha laid over [base].
  double contrast(Color foreground, Color ground, {Color? base}) {
    final behind = base == null ? ground : Color.alphaBlend(ground, base);
    final a = foreground.computeLuminance();
    final b = behind.computeLuminance();
    final (lighter, darker) = a > b ? (a, b) : (b, a);
    return (lighter + 0.05) / (darker + 0.05);
  }

  const aa = 4.5;

  for (final (name, colors) in <(String, CommyColors)>[
    ('dark', CommyColors.dark),
    ('light', CommyColors.light),
  ]) {
    group(name, () {
      test('text/tertiary reads on every ground it is used on', () {
        final grounds = <String, double>{
          'bg/surface': contrast(colors.textTertiary, colors.bgSurface),
          'bg/canvas': contrast(colors.textTertiary, colors.bgCanvas),
          'bg/raised': contrast(colors.textTertiary, colors.bgRaised),
          'bg/inset': contrast(colors.textTertiary, colors.bgInset),
          // Every text field's fill, under its hint.
          'bg/overlay': contrast(colors.textTertiary, colors.bgOverlay),
          'bg/group-header':
              contrast(colors.textTertiary, colors.bgGroupHeader),
          // The active server's row, when that server stopped answering.
          'status/connected/wash': contrast(
            colors.textTertiary,
            colors.statusConnectedWash,
            base: colors.bgSurface,
          ),
        };
        for (final MapEntry(key: ground, value: ratio) in grounds.entries) {
          expect(ratio, greaterThanOrEqualTo(aa), reason: 'on $ground');
        }
      });

      test('status/idle reads on its own wash', () {
        // The ПРЯМО badge of the routing screen, and every disabled rule.
        expect(
          contrast(
            colors.statusIdle,
            colors.statusIdleWash,
            base: colors.bgSurface,
          ),
          greaterThanOrEqualTo(aa),
        );
      });
    });
  }
}
