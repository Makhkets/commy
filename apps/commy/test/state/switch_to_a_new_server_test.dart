import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// A server that appears while the tunnel is up.
///
/// The running document is a snapshot of the servers that existed when the
/// tunnel started. A server imported after that — or brought in by a
/// subscription refresh an hour into the session — is in the list on the
/// screen and not in the selector of the core. Tapping it used to end in
/// "could not switch", for a user who had done nothing wrong, until they
/// thought of disconnecting first.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  Future<void> start(List<ProxyNode> nodes) async {
    harness = CommyTestHarness(nodes: nodes);
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(settingsProvider, (_, __) {}),
      container.listen(coreStatusProvider, (_, __) {}),
      container.listen(selectedNodeIdProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    await container.read(nodesProvider.future);
    await container.read(settingsProvider.future);
    await container.read(selectedNodeIdProvider.future);
  }

  TunnelController tunnel() =>
      container.read(tunnelControllerProvider.notifier);

  Future<void> connect(String nodeId) async {
    expect(await tunnel().connect(nodeId: nodeId), isTrue);
    await harness.core.status
        .firstWhere((status) => status is TunnelConnected)
        .timeout(const Duration(seconds: 5));
  }

  Future<ProxyGroup> selector() async => (await harness.core.proxies())
      .firstWhere((group) => group.tag == SingBoxTags.proxyGroup);

  /// Imports [node] the way a paste or a refresh does, and waits for the list.
  Future<void> addWhileConnected(ProxyNode node) async {
    await harness.nodeRepository.upsertAll(<ProxyNode>[node]);
    await container.read(nodesProvider.future);
    // Let the repository's change event reach the provider.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  test('a server the core already holds is switched to, not rebuilt', () async {
    final warsaw = testNode(id: 'node-2', name: 'Warsaw');
    await start(<ProxyNode>[testNode(), warsaw]);
    await connect('node-1');

    await tunnel().selectNode(warsaw);

    expect(harness.core.reloadCalls, 0);
    expect((await selector()).now, SingBoxTags.forNode(warsaw));
    expect(container.read(tunnelControllerProvider).failure, isNull);
  });

  test('a server that appeared after the start gets the document rebuilt',
      () async {
    await start(<ProxyNode>[testNode()]);
    await connect('node-1');
    final late = testNode(id: 'node-late', name: 'Late');
    await addWhileConnected(late);

    expect(
      (await selector()).all,
      isNot(contains(SingBoxTags.forNode(late))),
      reason: 'the premise: the running core has never heard of it',
    );

    await tunnel().selectNode(late);

    final state = container.read(tunnelControllerProvider);
    expect(state.failure, isNull);
    expect(harness.core.reloadCalls, 1);
    expect((await selector()).all, contains(SingBoxTags.forNode(late)));
    expect((await selector()).now, SingBoxTags.forNode(late));
    expect(container.read(selectedNodeIdProvider).value, 'node-late');
    expect(state.notice?.kind, TunnelNoticeKind.switched);
  });

  test('a new server that cannot be built leaves the old one selected',
      () async {
    await start(<ProxyNode>[testNode()]);
    await connect('node-1');
    // Reality with no public key: the builder refuses it by name.
    const broken = ProxyNode(
      id: 'node-broken',
      name: 'Broken',
      protocol: Protocol.vless,
      host: 'broken.example.net',
      port: 443,
      params: <String, Object?>{
        'uuid': '11111111-2222-3333-4444-555555555555',
        'security': 'reality',
        'sni': 's.example',
      },
    );
    await addWhileConnected(broken);

    await tunnel().selectNode(broken);

    final state = container.read(tunnelControllerProvider);
    expect(state.failure, isA<ConfigInvalidFailure>());
    expect(
      container.read(selectedNodeIdProvider).value,
      'node-1',
      reason: 'traffic still leaves through node-1; the list must say so',
    );
    expect((await selector()).now, SingBoxTags.forNode(testNode()));
  });

  test('one bad server in storage does not stop the others connecting',
      () async {
    const broken = ProxyNode(
      id: 'node-broken',
      name: 'Broken',
      protocol: Protocol.vless,
      host: 'broken.example.net',
      port: 443,
      params: <String, Object?>{
        'uuid': '11111111-2222-3333-4444-555555555555',
        'security': 'reality',
        'sni': 's.example',
      },
    );
    await start(<ProxyNode>[testNode(), broken]);

    await connect('node-1');

    expect(container.read(tunnelControllerProvider).failure, isNull);
    expect(
      (await selector()).all,
      <String>[SingBoxTags.forNode(testNode())],
    );
  });
}
