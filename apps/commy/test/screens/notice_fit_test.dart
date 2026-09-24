import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/auto_refresh_notice.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/measurement_report.dart';
import 'package:commy/src/widgets/notice_host.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_fonts.dart';
import '../support/commy_test_app.dart';

/// How many lines the toasts `NoticeHost` writes take on a 360 dp phone.
///
/// A toast sits at the top, over the app bar and the back button, and the
/// sentences were written to a two-line budget that nothing checked: the
/// ping summary shipped at three lines, and the automatic refresh's failure
/// at eleven. The test font draws every glyph a full em wide, so this file
/// alone loads the real ones — a line count in placeholder boxes means
/// nothing.
void main() {
  setUpAll(loadCommyFonts);
  tearDown(() => LocaleSettings.setLocaleSync(AppLocale.ru));

  /// The narrowest phone the layout is held to, with a status bar.
  const narrow = Size(360, 800);

  late _Measurement measurement;
  late AutoRefreshNotices autoRefresh;

  Future<void> pumpNarrow(WidgetTester tester, AppLocale locale) async {
    LocaleSettings.setLocaleSync(locale);
    tester.view
      ..physicalSize = narrow
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.reset);
    final harness = CommyTestHarness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(
        NoticeHost(
          child: Consumer(
            builder: (context, ref, child) {
              measurement =
                  ref.read(measurementProvider.notifier) as _Measurement;
              autoRefresh = ref.read(autoRefreshNoticeProvider.notifier);
              return const SizedBox.expand();
            },
          ),
        ),
        extra: [measurementProvider.overrideWith(_Measurement.new)],
      ),
    );
    await settle(tester);
  }

  /// The lines the toast's sentence was laid out in.
  int linesOf(WidgetTester tester) {
    final message = tester.widget<Toast>(find.byType(Toast)).message;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.byType(Toast), matching: find.text(message)),
    );
    final tops = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: message.length),
        )
        .map((box) => box.top)
        .toList()
      ..sort();
    var lines = 0;
    double? line;
    for (final top in tops) {
      // Runs of one line can sit a pixel apart; a new line is a line away.
      if (line == null || top - line > 4) {
        lines++;
        line = top;
      }
    }
    return lines;
  }

  Future<void> expire(WidgetTester tester) async {
    await tester.pump(ToastMessenger.actionDuration);
    await tester.pumpAndSettle();
  }

  final finland = testNode(id: 'fi-1', name: 'Finland', countryCode: 'FI');

  for (final locale in AppLocale.values) {
    group(locale.languageCode, () {
      late Translations t;
      // Real I/O for a deferred bundle, so here and not in a test body.
      setUpAll(() async {
        await LocaleSettings.setLocale(locale);
        t = await locale.build();
      });

      testWidgets('the usual ping summary is two lines', (tester) async {
        await pumpNarrow(tester, locale);

        measurement.finish(
          MeasurementReport(
            measured: 17,
            reachable: 15,
            node: finland,
            latency: const Duration(milliseconds: 90),
            skipped: 2,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<Toast>(find.byType(Toast)).message,
          contains(t.home.ping.skipped(count: 2)),
        );
        expect(linesOf(tester), lessThanOrEqualTo(2));

        await expire(tester);
      });

      testWidgets('a failed automatic refresh is two lines, action included',
          (tester) async {
        await pumpNarrow(tester, locale);

        autoRefresh.failed(
          name: 'My panel',
          failure: SubscriptionUnreachableFailure(
            url: Uri.parse('https://panel.example.net/sub/token'),
            cause: 'refused',
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.widget<Toast>(find.byType(Toast)).actionLabel,
          t.diagnostics.logs,
        );
        expect(linesOf(tester), lessThanOrEqualTo(2));

        await expire(tester);
      });

      testWidgets('an automatic refresh that worked is two lines',
          (tester) async {
        await pumpNarrow(tester, locale);

        autoRefresh.refreshed(name: 'My panel', count: 17);
        await tester.pumpAndSettle();

        expect(linesOf(tester), lessThanOrEqualTo(2));

        await expire(tester);
      });
    });
  }
}

/// A measurement controller the test can finish a run on.
class _Measurement extends MeasurementController {
  /// Writes the end of a run the way `measureAll` does.
  void finish(MeasurementReport report) =>
      state = MeasurementState(skipped: report.skipped, report: report);
}
