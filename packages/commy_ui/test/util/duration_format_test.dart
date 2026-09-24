import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommyDurationFormat', () {
    test('a session clock does not wrap after a day', () {
      expect(CommyDurationFormat.clock(Duration.zero), '00:00:00');
      expect(
        CommyDurationFormat.clock(const Duration(minutes: 12, seconds: 47)),
        '00:12:47',
      );
      expect(CommyDurationFormat.clock(const Duration(days: 3)), '72:00:00');
      expect(
        CommyDurationFormat.clock(const Duration(seconds: -5)),
        '00:00:00',
      );
    });

    // Seen on the emulator in the owner's language: a server row read
    // "110 ms" on a screen where every other unit was already Cyrillic.
    test('a round trip follows the locale like the byte units do', () {
      const latency = Duration(milliseconds: 110);
      expect(
        CommyDurationFormat.milliseconds(latency, locale: const Locale('en')),
        '110 ms',
      );
      expect(
        CommyDurationFormat.milliseconds(latency, locale: const Locale('ru')),
        '110 мс',
      );
      expect(CommyDurationFormat.milliseconds(latency), '110 ms');
    });
  });

  testWidgets('the latency badge reads its unit from the app locale',
      (tester) async {
    Future<void> pump(Locale locale) => tester.pumpWidget(
          Localizations(
            locale: locale,
            delegates: const <LocalizationsDelegate<dynamic>>[
              DefaultWidgetsLocalizations.delegate,
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Theme(
                data: CommyTheme.dark,
                child: const LatencyBadge(
                  latency: Duration(milliseconds: 84),
                ),
              ),
            ),
          ),
        );

    await pump(const Locale('ru'));
    expect(find.text('84 мс'), findsOneWidget);

    await pump(const Locale('en'));
    expect(find.text('84 ms'), findsOneWidget);
  });
}
