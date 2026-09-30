import 'package:commy/app.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/system_intent_listener.dart';
import 'package:commy/src/state/traffic_history.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The root widget, which everything else is rebuilt under.
void main() {
  testWidgets('a traffic tick does not rebuild the app shell', (tester) async {
    // The root keeps the traffic window awake for the statistics screen. It
    // used to watch it, and the window is a new value every second while
    // connected: the whole shell — MaterialApp, the router, both themes built
    // from scratch — was rebuilt once a second for a value it never reads.
    final harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides(
          extra: <Override>[
            systemSettingsProvider.overrideWithValue(const _QuietSystem()),
            systemIntentsProvider.overrideWithValue(const _NoIntents()),
          ],
        ),
        child: const CommyApp(),
      ),
    );
    await settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CommyApp)),
      listen: false,
    );

    await container.read(tunnelControllerProvider.notifier).connect();
    await tester.pump(const Duration(milliseconds: 200));
    final shell = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final window = container.read(trafficHistoryProvider);

    // The fake core samples every 50 ms.
    await tester.pump(const Duration(milliseconds: 200));

    expect(container.read(trafficHistoryProvider), isNot(window));
    expect(
      identical(tester.widget<MaterialApp>(find.byType(MaterialApp)), shell),
      isTrue,
    );

    await container.read(tunnelControllerProvider.notifier).disconnect();
    await tester.pump(const Duration(milliseconds: 100));
  });
}

/// Answers the platform questions the root asks, without a channel.
class _QuietSystem extends SystemSettings {
  const _QuietSystem();

  @override
  Future<bool> setStartOnBoot({required bool enabled}) async => true;

  @override
  Future<DeviceDescription?> deviceInfo() async => null;
}

/// Nothing handed over from outside the app.
class _NoIntents implements SystemIntents {
  const _NoIntents();

  @override
  Stream<SystemIntent> get events => const Stream<SystemIntent>.empty();
}
