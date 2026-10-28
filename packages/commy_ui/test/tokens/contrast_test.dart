import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contrast pairs of docs/04-design-system.md §2.3, computed from the
/// tokens themselves rather than copied into a table by hand.
///
/// The design protocol asks for every pair of `ink`, `ink-2` and `ink-3` to
/// be checked on `canvas`, `surface` and `surface-2` in both themes — it is
/// where generated interfaces fail most often — and for the graphics that
/// carry a state (the route's legs and stops, the border of a control) to
/// reach 3:1. Each ground below is one a token is really drawn on: the
/// search field's fill, the plate of the chosen server, a sheet.
void main() {
  /// WCAG 2.1 contrast of [foreground] drawn over [ground], which may be a
  /// wash with its own alpha laid over [base].
  double contrast(Color foreground, Color ground, {Color? base}) {
    final behind = base == null ? ground : Color.alphaBlend(ground, base);
    final front = Color.alphaBlend(foreground, behind);
    final a = front.computeLuminance();
    final b = behind.computeLuminance();
    final (lighter, darker) = a > b ? (a, b) : (b, a);
    return (lighter + 0.05) / (darker + 0.05);
  }

  const text = 4.5;
  const graphic = 3.0;

  for (final (name, colors, tags) in <(String, CommyColors, CommyTagColors)>[
    ('dark', CommyColors.dark, CommyTagColors.dark),
    ('light', CommyColors.light, CommyTagColors.light),
  ]) {
    group(name, () {
      /// Every opaque ground text is drawn on, and the tinted ones laid over
      /// the surface they sit on.
      final textGrounds = <String, (Color, Color?)>{
        'canvas': (colors.bgCanvas, null),
        'surface': (colors.bgSurface, null),
        'surface-2': (colors.bgOverlay, null),
        'surface-raised': (colors.bgRaised, null),
        'inset': (colors.bgInset, null),
        // The search field on the canvas and in a card.
        'fill on canvas': (colors.fill, colors.bgCanvas),
        'fill on surface': (colors.fill, colors.bgSurface),
        // The plate of the chosen server, live and not.
        'success wash on surface': (
          colors.statusConnectedWash,
          colors.bgSurface
        ),
      };

      for (final (role, ink) in <(String, Color)>[
        ('ink', colors.textPrimary),
        ('ink-2', colors.textSecondary),
        ('ink-3', colors.textTertiary),
      ]) {
        test('$role reads on every ground it is drawn on', () {
          for (final MapEntry(key: ground, value: (fill, base))
              in textGrounds.entries) {
            expect(
              contrast(ink, fill, base: base),
              greaterThanOrEqualTo(text),
              reason: '$role on $ground',
            );
          }
        });
      }

      // The protocol tags under a server name are 14 px text, so the full
      // 4.5:1, on every ground a server row is drawn on: the card, the picker
      // sheet, and the chosen row's plate over both — green while the tunnel
      // is up, the neutral fill while it is not.
      test('every tag hue reads on every ground a server row sits on', () {
        final grounds = <String, (Color, Color?)>{
          'surface': (colors.bgSurface, null),
          'surface-raised': (colors.bgRaised, null),
          'surface-2': (colors.bgOverlay, null),
          'success wash on surface': (
            colors.statusConnectedWash,
            colors.bgSurface
          ),
          'success wash on surface-raised': (
            colors.statusConnectedWash,
            colors.bgRaised
          ),
          'fill on surface': (colors.fill, colors.bgSurface),
          'fill on surface-raised': (colors.fill, colors.bgRaised),
          'wash on surface': (colors.accentWash, colors.bgSurface),
        };
        for (final hue in CommyTagHue.values) {
          for (final MapEntry(key: ground, value: (fill, base))
              in grounds.entries) {
            expect(
              contrast(tags.of(hue, colors), fill, base: base),
              greaterThanOrEqualTo(text),
              reason: '${hue.name} on $ground',
            );
          }
        }
      });

      test('every status word reads on the canvas, a card and its own wash',
          () {
        for (final (status, words, wash) in <(String, Color, Color)>[
          ('success', colors.statusConnected, colors.statusConnectedWash),
          ('warning', colors.statusConnecting, colors.statusConnectingWash),
          ('danger', colors.statusError, colors.statusErrorWash),
          ('info', colors.statusInfo, colors.statusInfoWash),
          ('neutral', colors.statusIdle, colors.statusIdleWash),
        ]) {
          expect(
            contrast(words, colors.bgCanvas),
            greaterThanOrEqualTo(text),
            reason: '$status on canvas',
          );
          expect(
            contrast(words, colors.bgSurface),
            greaterThanOrEqualTo(text),
            reason: '$status on surface',
          );
          expect(
            contrast(words, wash, base: colors.bgSurface),
            greaterThanOrEqualTo(text),
            reason: '$status on its own wash',
          );
        }
      });

      // The route's legs and stops, the edge of a control: graphics that say
      // something, so 3:1 against what they are drawn on.
      test('the graphics that carry a state reach 3:1', () {
        for (final (part, color) in <(String, Color)>[
          ('success fill', colors.statusConnectedSolid),
          ('warning fill', colors.statusConnectingSolid),
          ('danger fill', colors.statusErrorSolid),
          ('info fill', colors.statusInfoSolid),
          ('neutral fill', colors.statusIdleSolid),
          ('line-strong', colors.borderStrong),
          ('focus', colors.focusRing),
        ]) {
          for (final (ground, fill) in <(String, Color)>[
            ('canvas', colors.bgCanvas),
            ('surface', colors.bgSurface),
            ('surface-2', colors.bgOverlay),
          ]) {
            expect(
              contrast(color, fill),
              greaterThanOrEqualTo(graphic),
              reason: '$part on $ground',
            );
          }
        }
      });

      test('what is drawn on a fill reads on it', () {
        // Words on the danger button and on the action.
        expect(
          contrast(colors.statusErrorOnSolid, colors.statusErrorSolid),
          greaterThanOrEqualTo(text),
        );
        expect(
          contrast(colors.accentOnSolid, colors.accentSolid),
          greaterThanOrEqualTo(text),
        );
        // The cross on a broken stop, the tick on a switch.
        for (final (status, glyph, fill) in <(String, Color, Color)>[
          (
            'success',
            colors.statusConnectedOnSolid,
            colors.statusConnectedSolid
          ),
          (
            'warning',
            colors.statusConnectingOnSolid,
            colors.statusConnectingSolid
          ),
          ('info', colors.statusInfoOnSolid, colors.statusInfoSolid),
          ('neutral', colors.statusIdleOnSolid, colors.statusIdleSolid),
        ]) {
          expect(
            contrast(glyph, fill),
            greaterThanOrEqualTo(graphic),
            reason: 'a glyph on the $status fill',
          );
        }
      });

      test('the chosen segment is told from its track at 3:1', () {
        // The thumb's edge is what says which mode is on.
        expect(
          contrast(colors.borderStrong, colors.fill, base: colors.bgSurface),
          greaterThanOrEqualTo(graphic),
        );
        expect(
          contrast(colors.borderStrong, colors.fill, base: colors.bgCanvas),
          greaterThanOrEqualTo(graphic),
        );
      });
    });
  }
}
