import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The refresh button on a subscription card says how it went, either way.
///
/// A failure has always been a toast. A success was the card's "just now"
/// and nothing else, and the owner kept pressing the button to find out
/// whether anything had happened.
void main() {
  final t = Translations();

  const document = 'vless://11111111-2222-3333-4444-555555555555'
      '@nl-03.example.net:443?security=reality&type=tcp'
      '&pbk=xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k'
      '&sid=ab12cd34#Amsterdam%2003\n'
      'vless://11111111-2222-3333-4444-555555555555'
      '@pl-01.example.net:443?security=reality&type=tcp'
      '&pbk=xJ7bV3nQmR0cTfKzL2sYd8HqPwE1oUiA5gN6vB4rC9k'
      '&sid=ab12cd34#Warsaw%2001';

  late CommyTestHarness harness;

  setUp(() {
    harness = CommyTestHarness(
      subscriptions: <Subscription>[testSubscription()],
      nodes: <ProxyNode>[testNode(subscriptionId: 'sub-1')],
    )..subscriptionFetcher.body = document;
  });

  tearDown(() => harness.dispose());

  Future<void> pumpAndRefresh(
    WidgetTester tester, {
    List<Override> extra = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(400, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      harness.wrap(
        const HomeScreen(),
        status: const TunnelStatus.idle(),
        extra: extra,
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip(t.subscription.refresh));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a refresh that worked says how many servers came',
      (tester) async {
    await pumpAndRefresh(tester);

    expect(harness.subscriptionFetcher.callCount, 1);
    expect(find.text(t.subscription.refreshed(count: 2)), findsOneWidget);
  });

  testWidgets('a refresh that failed says why and offers the logs',
      (tester) async {
    harness.subscriptionFetcher.failure = SubscriptionUnreachableFailure(
      url: Uri.parse('https://panel.example.net/sub/token'),
      cause: 'the panel did not answer',
    );
    await pumpAndRefresh(tester);

    expect(find.text(t.error.subscriptionUnreachable.message), findsOneWidget);
    expect(find.text(t.error.openLogs), findsOneWidget);
    expect(
      find.textContaining(t.subscription.refreshed(count: 2)),
      findsNothing,
    );
  });

  // The scheduler's sweep at a cold start holds the controller for as long
  // as every due panel takes to answer. A tap on another card in that window
  // is turned away, and used to be turned away in silence: no spinner, no
  // toast, no refresh.
  testWidgets('a tap turned away while another panel refreshes says so',
      (tester) async {
    await pumpAndRefresh(
      tester,
      extra: <Override>[
        subscriptionControllerProvider.overrideWith(
          () => _BusyWith('sub-2'),
        ),
      ],
    );

    expect(harness.subscriptionFetcher.callCount, 0);
    expect(find.text(t.subscription.refreshBusy), findsOneWidget);
  });
}

/// A controller already busy refreshing [_id] when the screen opens.
class _BusyWith extends SubscriptionController {
  _BusyWith(this._id);

  final String _id;

  @override
  SubscriptionActionState build() => SubscriptionActionState(refreshingId: _id);
}
