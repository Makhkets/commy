import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The third text step and the idle tone clear WCAG AA on every ground they
/// are drawn on, not only on `bg/surface`.
///
/// The contrast table in docs/04-design-system.md checked them against the
/// surface alone, where the light #6C7178 made 4.9:1. The grounds they
/// actually sit on are greyer or tinted, and there it fell short: 4.33:1 in
/// the ПРЯМО badge on its own idle wash, 4.43:1 for every text field hint on
/// `bg/overlay`, 4.27:1 for the name of the active server when it stops
/// answering (on the connected wash) — and 4.46:1 for that same row in the
/// dark theme. The same figures as the table in docs/04.
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

  for (final (name, colors, tags) in <(String, CommyColors, CommyTagColors)>[
    ('dark', CommyColors.dark, CommyTagColors.dark),
    ('light', CommyColors.light, CommyTagColors.light),
  ]) {
    group(name, () {
      // The protocol tags under a server name are 12 px caption text, so
      // the full 4.5:1, on every ground a server row is drawn on: the card,
      // the picker sheet, and the active row's plate over both.
      test('every tag hue reads on every ground a server row sits on', () {
        final grounds = <String, (Color, Color?)>{
          'bg/surface': (colors.bgSurface, null),
          'bg/raised': (colors.bgRaised, null),
          'bg/overlay': (colors.bgOverlay, null),
          'status/connected/wash on bg/surface': (
            colors.statusConnectedWash,
            colors.bgSurface
          ),
          'status/connected/wash on bg/raised': (
            colors.statusConnectedWash,
            colors.bgRaised
          ),
          // A pointer over an ordinary row. The plate gets no hover wash,
          // and keyboard focus is a ring rather than a fill, so neither of
          // those changes the ground under the words.
          'accent/wash on bg/surface': (colors.accentWash, colors.bgSurface),
          'accent/wash on bg/raised': (colors.accentWash, colors.bgRaised),
        };
        for (final hue in CommyTagHue.values) {
          for (final MapEntry(key: ground, value: (fill, base))
              in grounds.entries) {
            expect(
              contrast(tags.of(hue, colors), fill, base: base),
              greaterThanOrEqualTo(aa),
              reason: '${hue.name} on $ground',
            );
          }
        }
      });

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
