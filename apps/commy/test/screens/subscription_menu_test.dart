import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/subscription_menu_sheet.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The two controls queue item #6 asked for: renaming and the interval.
///
/// Both write through the repository rather than through local state, so
/// every assertion here reads the stored row back — a menu that only updated
/// its own widget would look identical on screen and lose the change on the
/// next rebuild.
void main() {
  final t = Translations();

  late CommyTestHarness harness;

  /// Stands the menu up on a harness holding exactly [subscription].
  Future<void> pumpMenu(
    WidgetTester tester, {
    Subscription? subscription,
  }) async {
    final item = subscription ?? testSubscription();
    harness = CommyTestHarness(subscriptions: <Subscription>[item]);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: SubscriptionMenuSheet(subscription: item),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Subscription stored() => harness.subscriptionRepository.items.single;

  group('rename', () {
    testWidgets('writes the trimmed name and the header follows it',
        (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(t.subscription.menu.rename));
      await tester.pumpAndSettle();

      expect(find.text(t.subscription.rename.title), findsOneWidget);
      await tester.enterText(find.byType(CommyTextField), '  Home panel  ');
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(stored().name, 'Home panel');
      // The sheet stayed open on the renamed subscription.
      expect(find.text('Home panel'), findsWidgets);
      expect(find.text('My panel'), findsNothing);
    });

    testWidgets('refuses an empty name and writes nothing', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(t.subscription.menu.rename));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CommyTextField), '   ');
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(find.text(t.subscription.rename.empty), findsOneWidget);
      expect(stored().name, 'My panel');
    });
  });

  group('refresh interval', () {
    testWidgets('shows the stored interval and writes the picked one',
        (tester) async {
      await pumpMenu(tester);

      expect(find.text(t.time.hours(count: 12)), findsOneWidget);

      await tester.tap(find.text(t.subscription.menu.interval));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.time.hours(count: 6)));
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(stored().updateIntervalHours, 6);
    });

    testWidgets('a figure nobody offers snaps to the nearest button',
        (tester) async {
      // Panels put their own suggestion in `profile-update-interval`, and it
      // does not have to be one of the four the picker draws.
      final odd = testSubscription(updateIntervalHours: 11);
      await pumpMenu(tester, subscription: odd);

      await tester.tap(find.text(t.subscription.menu.interval));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(stored().updateIntervalHours, 12);
    });

    testWidgets('the interval survives auto refresh being off', (tester) async {
      final off = testSubscription(autoUpdate: false);
      await pumpMenu(tester, subscription: off);

      await tester.tap(find.text(t.subscription.menu.interval));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.time.hours(count: 1)));
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();

      expect(stored().updateIntervalHours, 1);
      expect(stored().autoUpdate, isFalse);
    });
  });
}
