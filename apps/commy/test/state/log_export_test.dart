import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';
import '../support/fake_repositories.dart';

/// docs/09-security-privacy.md, «Что вырезается всегда»: on an export the
/// address of the user's own server becomes `[server]`. The redactor could do
/// it all along, but the app never told it which addresses were the user's,
/// so a log pasted into a public chat carried the IP to block.
///
/// This builds the real log repository, which is the part under test; the
/// harness replaces it with a bare one for every other test.
void main() {
  late ProviderContainer container;
  late FakeNodeRepository nodes;

  setUp(() {
    nodes = FakeNodeRepository(<ProxyNode>[
      testNode(),
      // A panel's notice, addressed at nowhere. It is nobody's server, and
      // "listening on 0.0.0.0" must not come out as "[server]".
      testNode(id: 'notice', name: 'App not supported')
          .copyWith(host: '0.0.0.0', port: 1),
    ]);
    container = ProviderContainer(
      overrides: <Override>[nodeRepositoryProvider.overrideWithValue(nodes)],
    );
    addTearDown(() async {
      container.dispose();
      await nodes.dispose();
    });
  });

  Future<String> exported(String message) async {
    final handle = container.listen(nodesProvider, (_, __) {});
    addTearDown(handle.close);
    await container.read(nodesProvider.future);
    final logs = container.read(logRepositoryProvider);
    await logs.append(
      LogLine(
        level: LogLevel.warn,
        message: message,
        at: CommyTestHarness.now,
        tag: 'core',
      ),
    );
    return (await logs.export(redact: true)).valueOrNull!;
  }

  test("an export hides the address of the user's server", () async {
    final text = await exported(
      'connection: open outbound connection: '
      'dial tcp nl-03.example.net:443: i/o timeout',
    );

    expect(text, isNot(contains('nl-03.example.net')));
    expect(text, contains(Redact.serverPlaceholder));
  });

  test('an address that is not a server is left as it was', () async {
    final text = await exported('inbound/mixed: tcp server started at 0.0.0.0');

    expect(text, contains('0.0.0.0'));
    expect(text, isNot(contains(Redact.serverPlaceholder)));
  });
}
