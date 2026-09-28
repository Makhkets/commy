import 'package:commy/src/state/backup_controller.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// What a restore does around the use case: take the tunnel down first, and
/// read the selection again afterwards. Neither shows in the use case tests.
void main() {
  const oldServer = ProxyNode(
    id: 'old-server',
    name: 'Old',
    protocol: Protocol.trojan,
    host: 'old.example.com',
    port: 443,
    params: <String, Object?>{'password': 'old-secret'},
  );
  const newServer = ProxyNode(
    id: 'new-server',
    name: 'New',
    protocol: Protocol.trojan,
    host: 'new.example.com',
    port: 443,
    params: <String, Object?>{'password': 'new-secret'},
  );
  final snapshot = BackupSnapshot(
    createdAt: DateTime.utc(2026, 9, 29),
    appVersion: 'test',
    platform: 'android',
    nodes: const <ProxyNode>[newServer],
    selectedNodeId: newServer.id,
  );

  CommyTestHarness? harness;
  ProviderContainer? container;

  Future<(CommyTestHarness, ProviderContainer)> start({
    TunnelStatus? status,
  }) async {
    final host = CommyTestHarness(nodes: const <ProxyNode>[oldServer]);
    await host.settingsRepository.writeSelectedNodeId(oldServer.id);
    final scope = ProviderContainer(overrides: host.overrides(status: status))
      ..listen(coreStatusProvider, (_, __) {})
      ..listen(selectedNodeIdProvider, (_, __) {});
    await scope.read(coreStatusProvider.future);
    await scope.read(selectedNodeIdProvider.future);
    harness = host;
    container = scope;
    return (host, scope);
  }

  tearDown(() async {
    container?.dispose();
    await harness?.dispose();
    container = null;
    harness = null;
  });

  test('a running tunnel is taken down before anything is replaced', () async {
    final (host, scope) = await start(
      status: TunnelStatus.connected(
        since: CommyTestHarness.now,
        nodeId: oldServer.id,
      ),
    );

    final result =
        await scope.read(backupControllerProvider.notifier).restore(snapshot);

    expect(result.isOk, isTrue);
    expect(host.core.stopCalls, 1);
    expect(host.nodeRepository.nodes, const <ProxyNode>[newServer]);
  });

  test('an idle tunnel is left alone', () async {
    final (host, scope) = await start(status: const TunnelStatus.idle());

    await scope.read(backupControllerProvider.notifier).restore(snapshot);

    expect(host.core.stopCalls, 0);
  });

  test('the selection is read again: the screen shows the restored server',
      () async {
    final (_, scope) = await start(status: const TunnelStatus.idle());
    expect(scope.read(selectedNodeIdProvider).value, oldServer.id);

    await scope.read(backupControllerProvider.notifier).restore(snapshot);

    expect(await scope.read(selectedNodeIdProvider.future), newServer.id);
  });

  test('one flow at a time', () {
    final scope = ProviderContainer();
    addTearDown(scope.dispose);
    final controller = scope.read(backupControllerProvider.notifier);

    expect(controller.beginFlow(), isTrue);
    expect(controller.beginFlow(), isFalse);
    controller.endFlow();
    expect(controller.beginFlow(), isTrue);
  });

  test('the file name carries the day and nothing about the user', () {
    expect(
      BackupController.fileNameFor(DateTime(2026, 9, 5)),
      'commy-2026-09-05.commybackup',
    );
  });
}
