import 'dart:async';

import 'package:commy/src/state/app_visibility.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// When the app asks the core which server Auto is on.
///
/// Every five seconds, and only for the label on Home that shows it. The poll
/// used to run for as long as the tunnel was up on Auto: under Settings, where
/// each answer queued behind Home's paused subscription, and with the app in
/// the background, where nobody could read it.
///
/// `testWidgets` for its clock, not for widgets: half a minute of polling
/// passes in a few milliseconds.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;
  late List<ProviderSubscription<Object?>> handles;

  /// Connected on Auto, with Home's subscription open and answered once.
  Future<ProviderSubscription<Object?>> onAuto(
    WidgetTester tester,
    void Function() onAnswer,
  ) async {
    harness = CommyTestHarness(
      nodes: <ProxyNode>[testNode(), testNode(id: 'node-2', name: 'Warsaw')],
      settings: AppSettings.defaults.copyWith(autoSelect: true),
    );
    container = ProviderContainer(overrides: harness.overrides());
    handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(selectedNodeIdProvider, (_, __) {}),
    ];
    await tester.pump();
    unawaited(
      container.read(tunnelControllerProvider.notifier).connect(
            nodeId: 'node-1',
          ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(coreStatusProvider).value, isA<TunnelConnected>());

    final home = container.listen<AsyncValue<List<ProxyGroup>>>(
      proxyGroupsProvider,
      (_, __) => onAnswer(),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(container.read(autoNodeProvider)?.id, 'node-1');
    return home;
  }

  /// Closes everything before the test ends, so no timer outlives it.
  Future<void> tearDownAll(WidgetTester tester) async {
    for (final handle in handles) {
      handle.close();
    }
    container.dispose();
    await harness.dispose();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a covered Home is not polled, and asks at once when shown',
      (tester) async {
    var answers = 0;
    final home = await onAuto(tester, () => answers++);

    // Settings opens over Home: Riverpod pauses Home's subscription.
    home.pause();
    answers = 0;
    await tester.pump(const Duration(seconds: 30));
    home.resume();
    await tester.pump(const Duration(milliseconds: 10));

    // One fresh answer, not six queued ones.
    expect(answers, 1);
    home.close();
    await tearDownAll(tester);
  });

  testWidgets('the app in the background is not polled', (tester) async {
    var answers = 0;
    final home = await onAuto(tester, () => answers++);

    container.read(appVisibleProvider.notifier).hide();
    answers = 0;
    await tester.pump(const Duration(seconds: 30));
    expect(answers, 0);

    container.read(appVisibleProvider.notifier).show();
    await tester.pump(const Duration(milliseconds: 10));
    expect(answers, 1);

    // And it goes on polling once it is back.
    await tester.pump(const Duration(seconds: 5));
    expect(answers, 2);
    home.close();
    await tearDownAll(tester);
  });
}
