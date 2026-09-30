import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/widgets/subscription_menu_sheet.dart';
import 'package:commy/src/widgets/qr_sheet.dart';
import 'package:commy_data/commy_data.dart';
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

  group('QR', () {
    testWidgets('shows the subscription URL, and says what that hands over',
        (tester) async {
      // Sharing a subscription shares the access token, not a server. The
      // warning is the difference between this sheet and the node one, and
      // it has to be on screen with the code rather than behind it.
      await pumpMenu(tester);

      await tester.tap(find.text(t.subscription.menu.showQr));
      await tester.pumpAndSettle();

      final sheet = tester.widget<QrSheet>(find.byType(QrSheet));
      expect(sheet.payload, stored().url.toString());
      expect(find.text(t.qr.subscriptionWarning), findsOneWidget);
    });
  });

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

  group('User-Agent', () {
    // docs/06 promises the override "in the profile settings" and docs/17
    // sends the owner to "subscription menu -> User-Agent" when servers go
    // missing. The field went all the way to the request; nothing in the app
    // could set it.
    Future<void> openPicker(WidgetTester tester) async {
      await tester.ensureVisible(find.text(t.subscription.menu.userAgent));
      await tester.tap(find.text(t.subscription.menu.userAgent));
      await tester.pumpAndSettle();
      expect(find.text(t.subscription.userAgent.body), findsOneWidget);
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.text(t.common.save));
      await tester.tap(find.text(t.common.save));
      await tester.pumpAndSettle();
    }

    testWidgets('a preset is one tap, and the row names it', (tester) async {
      await pumpMenu(tester);
      expect(find.text(CommyUserAgent.product), findsOneWidget);

      await openPicker(tester);
      await tester.ensureVisible(find.text('v2rayNG'));
      await tester.tap(find.text('v2rayNG'));
      await tester.pump();
      await save(tester);

      expect(stored().userAgentOverride, CommyUserAgent.presets['v2rayNG']);
      expect(find.text('v2rayNG'), findsOneWidget);
    });

    testWidgets('a new choice is fetched with at once', (tester) async {
      // Picked because servers were missing: waiting for the next scheduled
      // refresh made the choice look like it had done nothing.
      await pumpMenu(tester);

      await openPicker(tester);
      await tester.ensureVisible(find.text('v2rayNG'));
      await tester.tap(find.text('v2rayNG'));
      await tester.pump();
      await save(tester);

      expect(harness.subscriptionFetcher.callCount, 1);
      expect(
        harness.subscriptionFetcher.userAgents.single,
        CommyUserAgent.presets['v2rayNG'],
      );
    });

    testWidgets('saving the choice already made fetches nothing',
        (tester) async {
      await pumpMenu(tester);

      await openPicker(tester);
      await save(tester);

      expect(stored().userAgentOverride, isNull);
      expect(harness.subscriptionFetcher.callCount, 0);
    });

    testWidgets("the user's own string is kept as typed", (tester) async {
      await pumpMenu(tester);

      await openPicker(tester);
      await tester.ensureVisible(find.text(t.subscription.userAgent.custom));
      await tester.tap(find.text(t.subscription.userAgent.custom));
      await tester.pump();
      await tester.enterText(find.byType(CommyTextField), '  Happ/3.9.0 ');
      await save(tester);

      expect(stored().userAgentOverride, 'Happ/3.9.0');
    });

    testWidgets('a string no header can carry is refused, not saved',
        (tester) async {
      // dart:io throws on a header outside printable ASCII, and every
      // refresh would then read as a server that is not answering.
      await pumpMenu(tester);

      await openPicker(tester);
      await tester.ensureVisible(find.text(t.subscription.userAgent.custom));
      await tester.tap(find.text(t.subscription.userAgent.custom));
      await tester.pump();
      await tester.enterText(find.byType(CommyTextField), 'Хэпп/1.0');
      await save(tester);

      expect(find.text(t.subscription.userAgent.invalid), findsOneWidget);
      expect(stored().userAgentOverride, isNull);
    });

    testWidgets('the default is a choice too, and it clears the override',
        (tester) async {
      await pumpMenu(
        tester,
        subscription: testSubscription().copyWith(
          userAgentOverride: 'Happ/3.9.0',
        ),
      );
      expect(find.text('Happ/3.9.0'), findsOneWidget);

      await openPicker(tester);
      await tester.tap(find.text(t.subscription.userAgent.honest));
      await tester.pump();
      await save(tester);

      expect(stored().userAgentOverride, isNull);
      expect(find.text(CommyUserAgent.product), findsOneWidget);
    });
  });
}
