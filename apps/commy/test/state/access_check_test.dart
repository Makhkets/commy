import 'package:commy/src/state/access_check.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// The answer under the route's internet stop.
///
/// A check reports through a notice, which the toast host clears the moment
/// it has shown it; the route needs the answer for as long as it stays true.
/// It has to outlive the toast and die with the tunnel it describes.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  setUp(() async {
    harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
    await harness.settingsRepository.writeSelectedNodeId('node-1');
    container = ProviderContainer(overrides: harness.overrides());
    final handles = <ProviderSubscription<Object?>>[
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(tunnelControllerProvider, (_, __) {}),
      container.listen(accessCheckProvider, (_, __) {}),
      container.listen(nodesProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
    ];
    addTearDown(() async {
      for (final handle in handles) {
        handle.close();
      }
      container.dispose();
      await harness.dispose();
    });
    await container.read(nodesProvider.future);
    await container.read(settingsProvider.future);
    await pumpEventQueue();
  });

  TunnelController tunnel() =>
      container.read(tunnelControllerProvider.notifier);

  Future<void> waitFor(bool Function() done) async {
    for (var tries = 0; tries < 200 && !done(); tries++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(done(), isTrue, reason: 'timed out');
  }

  Future<void> connect() async {
    expect(await tunnel().connect(), isTrue);
    await waitFor(
      () => container.read(coreStatusProvider).value is TunnelConnected,
    );
  }

  test('nothing is known before a check', () async {
    expect(container.read(accessCheckProvider), isNull);
    await connect();
    expect(container.read(accessCheckProvider), isNull);
  });

  test('a passed check is kept after its notice is cleared', () async {
    await connect();
    await tunnel().check();
    await waitFor(() => container.read(accessCheckProvider) != null);

    final answer = container.read(accessCheckProvider)!;
    expect(answer.passed, isTrue);
    expect(answer.milliseconds, isNotNull);

    // The toast host does this as soon as the toast is up.
    tunnel().clearNotice();
    await pumpEventQueue();
    expect(container.read(accessCheckProvider), answer);
  });

  test('the answer goes with the tunnel it was about', () async {
    await connect();
    await tunnel().check();
    await waitFor(() => container.read(accessCheckProvider) != null);

    await tunnel().disconnect();
    await waitFor(
      () => container.read(coreStatusProvider).value is TunnelIdle,
    );
    await pumpEventQueue();
    expect(container.read(accessCheckProvider), isNull);
  });
}
