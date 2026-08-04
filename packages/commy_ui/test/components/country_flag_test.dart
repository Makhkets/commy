import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_host.dart';

void main() {
  useCommyGoldens();

  const codes = <String>[
    'NL', 'DE', 'FR', 'PL', 'LT', 'RU', 'LV', 'FI', 'JP', 'EU', //
    'US', 'GB', 'SE', 'NO', 'CH', 'TR', 'AT', 'ES', 'IT', //
  ];

  group('CountryFlag', () {
    testWidgets('is always 26 × 20, whatever the code', (tester) async {
      for (final code in <String?>[...codes, 'UK', null, '', 'zz']) {
        await pumpCommy(tester, child: CountryFlag(countryCode: code));
        expect(
          tester.getSize(find.byType(CountryFlag)),
          const Size(CommySizes.flagWidth, CommySizes.flagHeight),
          reason: 'code $code',
        );
        expect(tester.takeException(), isNull, reason: 'code $code');
      }
    });

    test('recognises every code it draws, in any case', () {
      for (final code in codes) {
        expect(CountryFlag.isSupported(code), isTrue, reason: code);
        expect(CountryFlag.isSupported(code.toLowerCase()), isTrue);
        expect(CountryFlag.isSupported('  $code  '), isTrue);
      }
    });

    test('accepts UK as an alias of GB', () {
      expect(CountryFlag.isSupported('UK'), isTrue);
    });

    test('reports an unknown country instead of pretending', () {
      expect(CountryFlag.isSupported(null), isFalse);
      expect(CountryFlag.isSupported(''), isFalse);
      expect(CountryFlag.isSupported('ZZ'), isFalse);
      expect(CountryFlag.isSupported('Netherlands'), isFalse);
    });

    testWidgets('is invisible to a screen reader without a label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpCommy(tester, child: const CountryFlag(countryCode: 'NL'));
      expect(find.bySemanticsLabel('Нидерланды'), findsNothing);

      await pumpCommy(
        tester,
        child: const CountryFlag(
          countryCode: 'NL',
          semanticLabel: 'Нидерланды',
        ),
      );
      expect(find.bySemanticsLabel('Нидерланды'), findsOneWidget);
      handle.dispose();
    });
  });

  group('NodeTile', () {
    testWidgets('builds its own flag from the country code', (tester) async {
      await pumpCommy(
        tester,
        size: const Size(390, 120),
        child: const NodeTile(name: 'Amsterdam 03', countryCode: 'NL'),
      );
      final flag = tester.widget<CountryFlag>(find.byType(CountryFlag));
      expect(flag.countryCode, 'NL');
    });

    testWidgets('keeps the flag slot when the country is unknown', (
      tester,
    ) async {
      // Otherwise every name in a mixed list would start on a different
      // column, which is the one thing that makes a long list scannable.
      await pumpCommy(
        tester,
        size: const Size(390, 120),
        child: const NodeTile(name: 'Ручной узел'),
      );
      expect(find.byType(CountryFlag), findsOneWidget);
    });
  });
}
