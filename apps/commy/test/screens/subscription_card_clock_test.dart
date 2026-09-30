import 'dart:async';

import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What the one-second clock costs a subscription card.
///
/// The card reads the clock for "2 h ago", the days left and the tone of the
/// header. It used to be rebuilt on every tick, and with it every server row
/// of the card — a panel of two hundred servers rebuilt two hundred rows a
/// second, all year, to redraw a line that changes once an hour.
void main() {
  late StreamController<DateTime> clock;

  setUp(() => clock = StreamController<DateTime>.broadcast());
  tearDown(() => clock.close());

  Future<void> pumpHome(WidgetTester tester, Duration updatedAgo) async {
    final harness = CommyTestHarness(
      subscriptions: <Subscription>[testSubscription(updatedAgo: updatedAgo)],
      nodes: <ProxyNode>[
        for (var i = 0; i < 3; i++)
          testNode(id: 'node-$i', name: 'Server $i', subscriptionId: 'sub-1'),
      ],
      clock: clock.stream,
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
    clock.add(CommyTestHarness.now);
    await settle(tester);
  }

  Future<void> tick(WidgetTester tester, int seconds) async {
    clock.add(CommyTestHarness.now.add(Duration(seconds: seconds)));
    await settle(tester);
  }

  NodeRow firstRow(WidgetTester tester) =>
      tester.widget<NodeRow>(find.byType(NodeRow).first);

  String subtitle(WidgetTester tester) =>
      tester.widget<SubscriptionCard>(find.byType(SubscriptionCard)).subtitle!;

  testWidgets('a tick that changes nothing on the card rebuilds no row',
      (tester) async {
    await pumpHome(tester, const Duration(hours: 2));
    final row = firstRow(tester);
    final before = subtitle(tester);

    await tick(tester, 1);
    await tick(tester, 2);

    expect(subtitle(tester), before);
    expect(identical(firstRow(tester), row), isTrue);
  });

  testWidgets('the seconds after a refresh still count up', (tester) async {
    await pumpHome(tester, const Duration(seconds: 5));
    final before = subtitle(tester);

    await tick(tester, 1);

    expect(subtitle(tester), isNot(before));
  });
}
