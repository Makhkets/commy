import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/settings/routing_screen.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Routing profiles (D10) and their links (D11) on the routing screen.
///
/// Every assertion reads the repository the config builder reads from:
/// what matters is which rules are in force after a tap, not which chip is
/// highlighted.
void main() {
  final t = Translations();
  const ruDirect = RoutingPolicy(
    rules: <RoutingRule>[
      RoutingRule(id: 'r1', matcher: 'geosite:ru', action: RuleAction.direct),
    ],
  );

  late CommyTestHarness harness;

  // A chip shows its label upper-cased.
  Finder chip(String label) => find.widgetWithText(CommyChip, label);

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(560, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    harness = CommyTestHarness();
    addTearDown(harness.dispose);
    await harness.routingRepository.write(ruDirect);
    await tester.pumpWidget(harness.wrap(const RoutingScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> createProfile(WidgetTester tester, String name) async {
    await tester.tap(chip(t.routing.profiles.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, name);
    await tester.tap(find.text(t.routing.profiles.save));
    await tester.pumpAndSettle();
  }

  testWidgets('one setup reads as Main until a second is made', (tester) async {
    await pumpScreen(tester);

    expect(chip(t.routing.profiles.main), findsOneWidget);
    expect(harness.routingRepository.profiles.isInUse, isFalse);
  });

  testWidgets('a new profile copies the rules and keeps the old as Main',
      (tester) async {
    await pumpScreen(tester);

    await createProfile(tester, 'Travel');

    final profiles = harness.routingRepository.profiles;
    final names = <String>[for (final p in profiles.profiles) p.name];
    expect(names, <String>[t.routing.profiles.main, 'Travel']);
    expect(profiles.active?.name, 'Travel');
    expect(harness.routingRepository.policy, ruDirect);
  });

  testWidgets('a tap switches the rules in force and keeps the edits',
      (tester) async {
    await pumpScreen(tester);
    await createProfile(tester, 'Travel');

    // Edit Travel: everything through the server.
    await tester.tap(find.text(t.routing.mode.global));
    await tester.pumpAndSettle();
    expect(harness.routingRepository.policy.mode, RoutingMode.global);

    await tester.tap(chip(t.routing.profiles.main));
    await tester.pumpAndSettle();

    expect(harness.routingRepository.policy, ruDirect);
    final travel = harness.routingRepository.profiles.profiles
        .firstWhere((p) => p.name == 'Travel');
    expect(travel.policy.mode, RoutingMode.global);
  });

  testWidgets('sharing copies a link that brings the same rules back',
      (tester) async {
    await pumpScreen(tester);
    await createProfile(tester, 'RU direct');

    await tester.tap(chip('RU direct'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.routing.profiles.share));
    await tester.pumpAndSettle();

    final link = harness.clipboard.text!;
    expect(link, startsWith(RoutingProfileLink.prefix));
    final back = RoutingProfileLink.decode(link, id: 'x')!;
    expect(back.name, 'RU direct');
    expect(back.policy.rules.single.matcher, 'geosite:ru');
  });

  test('a shared link is offered, not applied, until the user says so',
      () async {
    final harness = CommyTestHarness();
    final container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    const shared = RoutingProfile(
      id: 'shared',
      name: 'Friend',
      policy: RoutingPolicy(mode: RoutingMode.global),
    );

    await container
        .read(importControllerProvider.notifier)
        .importText(RoutingProfileLink.encode(shared));

    final state = container.read(importControllerProvider);
    expect(state.routingProfile?.name, 'Friend');
    expect(harness.routingRepository.policy, RoutingPolicy.defaults);
    expect(harness.subscriptionFetcher.requests, isEmpty);

    await container
        .read(importControllerProvider.notifier)
        .importText('${RoutingProfileLink.prefix}broken');
    expect(container.read(importControllerProvider).failure, isNotNull);
  });
}
