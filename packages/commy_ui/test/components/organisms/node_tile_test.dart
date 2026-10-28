import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        descriptors: const <NodeTag>[
          NodeTag('VLESS', hue: CommyTagHue.azure),
          NodeTag('Reality', hue: CommyTagHue.iris),
          NodeTag('TCP'),
        ],
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
    // And the protocol keeps its word but loses its hue.
    final line = tester.widget<NodeTagLine>(find.byType(NodeTagLine));
    expect(line.muted, isTrue);
    expect(line.mutedColor, colors.textTertiary);
  });

  testWidgets('the protocol line is drawn in its hues', (tester) async {
    await pumpTile(tester, reachable: true);

    final element = tester.element(find.byType(NodeTile));
    final tags = element.tagColors;
    final colors = element.colors;
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(NodeTagLine),
        matching: find.byType(RichText),
      ),
    );
    final spans = <TextSpan>[];
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        spans.add(span);
      }
      return true;
    });
    Color? colorOf(String text) {
      final span = spans.firstWhere((span) => span.text == text);
      return span.style?.color;
    }

    expect(colorOf('VLESS'), tags.azure);
    expect(colorOf('Reality'), tags.iris);
    // The transport and the dots between words are the caption's own.
    expect(colorOf('TCP'), isNull);
    final line = tester.widget<Text>(
      find.descendant(
        of: find.byType(NodeTagLine),
        matching: find.byType(Text),
      ),
    );
    expect(line.textSpan?.style?.color, colors.textSecondary);
    expect(
      tester.widget<NodeTile>(find.byType(NodeTile)).descriptorLine,
      'VLESS, Reality, TCP',
    );
  });

  // Material's default focus fill — 12 % black or white under the text —
  // took the protocol tags below AA on the plate. Focus is a ring here, as
  // everywhere else in the system.
  testWidgets('keyboard focus is a ring over the row, not a fill',
      (tester) async {
    var taps = 0;
    await pumpCommy(
      tester,
      size: const Size(360, 120),
      child: NodeTile(
        name: 'Frankfurt 02',
        countryCode: 'DE',
        isActive: true,
        onTap: () => taps++,
      ),
    );
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    final colors = tester.element(find.byType(NodeTile)).colors;
    final plate = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(NodeTile),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final ring = plate.foregroundDecoration! as BoxDecoration;
    expect((ring.border! as Border).top.color, colors.focusRing);
    // The ink well itself never takes focus, so it never paints its fill.
    expect(
      tester.widget<InkWell>(find.byType(InkWell)).canRequestFocus,
      isFalse,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('the active server is a plate with an edge, not a bar',
      (tester) async {
    await pumpCommy(
      tester,
      size: const Size(360, 120),
      child: NodeTile(
        name: 'Frankfurt 02',
        countryCode: 'DE',
        isActive: true,
        onTap: () {},
      ),
    );

    final colors = tester.element(find.byType(NodeTile)).colors;
    final plate = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(NodeTile),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = plate.decoration! as BoxDecoration;
    expect(decoration.color, colors.statusConnectedWash);
    expect(
      (decoration.border! as Border).top.color,
      colors.statusConnected,
    );
    expect(
      tester.getSemantics(find.byType(NodeTile).first),
      isSemantics(isSelected: true),
    );
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
