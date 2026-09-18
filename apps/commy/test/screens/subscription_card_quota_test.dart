import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What the card says about traffic when the plan has no ceiling.
///
/// On a device the line under the header read «без лимита» and nothing else —
/// a lone caption where a limited plan has a bar and two numbers. The panel
/// had still reported how much went through, and that is the one number an
/// unlimited plan has.
void main() {
  late Translations t;

  setUpAll(() async {
    await LocaleSettings.setLocale(AppLocale.ru);
    t = AppLocale.ru.buildSync();
  });

  Future<SubscriptionCard> pumpCard(
    WidgetTester tester,
    SubscriptionUserInfo info,
  ) async {
    final harness = CommyTestHarness(
      subscriptions: <Subscription>[
        testSubscription().copyWith(userInfo: info),
      ],
      nodes: <ProxyNode>[testNode(subscriptionId: 'sub-1')],
    );
    addTearDown(harness.dispose);
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      harness.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
    );
    await settle(tester);
    return tester.widget<SubscriptionCard>(find.byType(SubscriptionCard));
  }

  testWidgets('an unlimited plan shows what was used next to the word',
      (tester) async {
    final card = await pumpCard(
      tester,
      const SubscriptionUserInfo(upload: 1 << 30, download: 3 << 30, total: 0),
    );

    expect(
      card.quotaLabel,
      t.subscription.usedUnlimited(used: CommyByteFormat.bytes(4 << 30)),
    );
    expect(card.quotaRatio, isNull, reason: 'No ceiling, so no bar.');
  });

  testWidgets('with nothing used yet it is just the word', (tester) async {
    final card = await pumpCard(
      tester,
      const SubscriptionUserInfo(upload: 0, download: 0, total: 0),
    );

    expect(card.quotaLabel, t.subscription.unlimited);
  });

  testWidgets('a limited plan is unchanged: used of total', (tester) async {
    final card = await pumpCard(
      tester,
      const SubscriptionUserInfo(
        upload: 1 << 30,
        download: 1 << 30,
        total: 10 << 30,
      ),
    );

    expect(
      card.quotaLabel,
      t.subscription.quota(
        used: CommyByteFormat.bytes(2 << 30),
        total: CommyByteFormat.bytes(10 << 30),
      ),
    );
  });
}
