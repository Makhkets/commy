import 'dart:convert';
import 'dart:io';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/screens/home/home_screen.dart';
import 'package:commy/src/screens/home/widgets/subscription_menu_sheet.dart';
import 'package:commy/src/screens/settings/settings_screen.dart';
import 'package:commy/src/state/import_controller.dart';
import 'package:commy/src/widgets/settings_tile.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The user's side of docs/adr/0019-subscription-domain-recovery.md: the
/// question a signed move puts on the card, the switch in the menu, the
/// exception's row in "network silence", and a manifest signed by Go's own
/// `crypto/ed25519` pinned by the shipping code path on import.
void main() {
  final t = Translations();
  final vector = jsonDecode(
    File('../../packages/commy_data/test/recovery/fixtures/'
            'manifest_vector.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  final manifest = SignedManifest.parse(vector['compact']! as String)!.manifest;

  SubscriptionRecovery asked() {
    final pinned = SubscriptionRecovery.pinned(manifest);
    return pinned.copyWith(
      pending: PendingDomainChange(
        manifest: RecoveryManifest(
          id: manifest.id,
          seq: manifest.seq + 1,
          issuedAt: manifest.issuedAt,
          origin: Uri.parse('https://sub.example.online'),
          key: manifest.key,
          name: 'AXM VPN',
        ),
        source: RecoverySource.rendezvous,
      ),
    );
  }

  Future<CommyTestHarness> pumpHome(
    WidgetTester tester,
    SubscriptionRecovery recovery,
  ) async {
    final harness = CommyTestHarness(
      subscriptions: <Subscription>[
        testSubscription().copyWith(recovery: recovery),
      ],
      nodes: <ProxyNode>[testNode(subscriptionId: 'sub-1')],
    );
    addTearDown(harness.dispose);
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(const HomeScreen(), status: const TunnelStatus.idle()),
    );
    await settle(tester);
    return harness;
  }

  testWidgets('a signed move is a question on the card, with both addresses',
      (tester) async {
    await pumpHome(tester, asked());

    expect(find.text(t.subscription.recovery.changedTitle), findsOneWidget);
    expect(
      find.text(
        t.subscription.recovery.changedBody(
          name: 'AXM VPN',
          from: 'panel.example.net',
          to: 'sub.example.online',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('accepting moves the card and fetches it from the new address',
      (tester) async {
    final harness = await pumpHome(tester, asked());

    await tester.tap(find.text(t.subscription.recovery.accept));
    await settle(tester);

    final stored = harness.subscriptionRepository.items.single;
    expect(stored.url, Uri.parse('https://sub.example.online/sub/token'));
    expect(stored.recovery?.pending, isNull);
    expect(
      harness.subscriptionFetcher.requests,
      <Uri>[Uri.parse('https://sub.example.online/sub/token')],
    );
    expect(find.text(t.subscription.recovery.changedTitle), findsNothing);
  });

  testWidgets('declining keeps the address and asks no more', (tester) async {
    final harness = await pumpHome(tester, asked());

    await tester.tap(find.text(t.subscription.recovery.decline));
    await settle(tester);

    final stored = harness.subscriptionRepository.items.single;
    expect(stored.url, Uri.parse('https://panel.example.net/sub/token'));
    expect(stored.recovery?.declinedSeq, manifest.seq + 1);
    expect(harness.subscriptionFetcher.requests, isEmpty);
    expect(find.text(t.subscription.recovery.changedTitle), findsNothing);
  });

  testWidgets('the menu names where recovery would ask, and switches it off',
      (tester) async {
    final harness = CommyTestHarness(
      subscriptions: <Subscription>[
        testSubscription().copyWith(
          recovery: SubscriptionRecovery.pinned(manifest),
        ),
      ],
    );
    addTearDown(harness.dispose);
    tester.view
      ..physicalSize = const Size(420, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      harness.wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: SubscriptionMenuSheet(
              subscription: harness.subscriptionRepository.items.single,
            ),
          ),
        ),
      ),
    );
    await settle(tester);

    expect(
      find.text(
        t.subscription.recovery.statusPoint(
          mirrors: 1,
          host: 'commy.example.net',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(SettingsTile, t.subscription.recovery.title),
        matching: find.byType(CommySwitch),
      ),
    );
    await settle(tester);

    expect(
      harness.subscriptionRepository.items.single.recovery?.enabled,
      isFalse,
    );
  });

  testWidgets('network silence lists the meeting point only when there is one',
      (tester) async {
    Future<void> pumpSettings(List<Subscription> subscriptions) async {
      final harness = CommyTestHarness(subscriptions: subscriptions);
      addTearDown(harness.dispose);
      tester.view
        ..physicalSize = const Size(420, 2600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness.wrap(const SettingsScreen()));
      await settle(tester);
    }

    await pumpSettings(<Subscription>[testSubscription()]);
    expect(find.text(t.settings.silence.recovery), findsNothing);

    await pumpSettings(<Subscription>[
      testSubscription().copyWith(
        recovery: SubscriptionRecovery.pinned(manifest),
      ),
    ]);
    expect(find.text(t.settings.silence.recovery), findsOneWidget);
    expect(find.textContaining('commy.example.net'), findsOneWidget);
  });

  test('importing a subscription pins the key its provider signed with',
      () async {
    final harness = CommyTestHarness();
    final container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    harness.subscriptionFetcher
      ..body = 'vless://11111111-2222-3333-4444-555555555555'
          '@nl-03.example.net:443?security=tls#Amsterdam'
      ..manifest = vector['compact']! as String;

    await container
        .read(importControllerProvider.notifier)
        .importText('https://sub.example.com/sub/TOKEN');

    final recovery = harness.subscriptionRepository.items.single.recovery;
    expect(recovery?.key, vector['public_key']);
    expect(recovery?.id, 'axm');
    expect(harness.rendezvous.visits, isEmpty);
  });

  test('a forged manifest pins nothing', () async {
    final harness = CommyTestHarness();
    final container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    harness.subscriptionFetcher
      ..body = 'vless://11111111-2222-3333-4444-555555555555'
          '@nl-03.example.net:443?security=tls#Amsterdam'
      ..manifest = vector['tampered']! as String;

    await container
        .read(importControllerProvider.notifier)
        .importText('https://sub.example.com/sub/TOKEN');

    expect(harness.subscriptionRepository.items.single.recovery, isNull);
  });
}
