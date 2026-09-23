import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/home/widgets/panel_notice_row.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What a panel sends instead of servers, on the subscription card.
///
/// Seen on the emulator against a panel with a device limit: with the device
/// identifier switched off the card said "App not supported" and nothing
/// else, and the switch that fixes it was two screens away, on a page that
/// does not mention panels by name.
void main() {
  final subscription = Subscription(
    id: 'sub-1',
    name: 'Panel',
    url: Uri.parse('https://panel.example.com/sub/token'),
  );

  const notice = ProxyNode(
    id: 'notice-1',
    name: 'App not supported',
    protocol: Protocol.vless,
    host: '0.0.0.0',
    port: 1,
    subscriptionId: 'sub-1',
  );

  Future<CommyTestHarness> pumpCard(
    WidgetTester tester, {
    required bool sendDeviceId,
  }) async {
    final harness = CommyTestHarness(
      nodes: const <ProxyNode>[notice],
      subscriptions: <Subscription>[subscription],
      settings: AppSettings.defaults.copyWith(sendDeviceId: sendDeviceId),
    );
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      harness.wrap(
        const HomeScreen(),
        status: const TunnelStatus.idle(),
      ),
    );
    await settle(tester);
    return harness;
  }

  testWidgets('with the identifier off, says so and offers to turn it on',
      (tester) async {
    final harness = await pumpCard(tester, sendDeviceId: false);
    final t = Translations();

    expect(find.byType(PanelNoticeRow), findsOneWidget);
    expect(find.text('App not supported'), findsOneWidget);
    expect(find.text(t.subscription.deviceIdOff), findsOneWidget);

    await tester.ensureVisible(find.text(t.subscription.sendDeviceId));
    await settle(tester);
    await tester.tap(find.text(t.subscription.sendDeviceId));
    await settle(tester);

    final settings = (await harness.settingsRepository.read()).valueOrNull;
    expect(settings?.sendDeviceId, isTrue);
    expect(
      harness.subscriptionFetcher.callCount,
      1,
      reason: 'Turning it on is only half the fix; the panel has to be '
          'asked again.',
    );
  });

  testWidgets('with the identifier on, the panel speaks for itself',
      (tester) async {
    await pumpCard(tester, sendDeviceId: true);
    final t = Translations();

    expect(find.text('App not supported'), findsOneWidget);
    expect(find.text(t.subscription.deviceIdOff), findsNothing);
    expect(find.text(t.subscription.sendDeviceId), findsNothing);
  });
}
