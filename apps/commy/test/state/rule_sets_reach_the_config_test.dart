import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';
import '../support/fake_repositories.dart';

/// The half of queue item #13 that is not a screen.
///
/// Downloading a rule set is only worth anything if the generated document
/// then points the core at it. Until this session `ruleSetDirectory` and
/// `availableRuleSets` were never supplied, so every `geosite:` rule was
/// dropped with a warning no matter what was on disk — which made the whole
/// feature look broken from the one place a user would check.
void main() {
  late CommyTestHarness harness;
  late ProviderContainer container;

  Future<void> start({required List<String> matchers}) async {
    harness = CommyTestHarness(nodes: <ProxyNode>[testNode()]);
    await harness.routingRepository.write(
      RoutingPolicy.defaults.copyWith(
        mode: RoutingMode.rules,
        rules: <RoutingRule>[
          for (final matcher in matchers)
            RoutingRule(
              id: matcher,
              matcher: matcher,
              action: RuleAction.direct,
            ),
        ],
      ),
    );
    container = ProviderContainer(overrides: harness.overrides());
    addTearDown(() async {
      container.dispose();
      await harness.dispose();
    });
    final handles = <ProviderSubscription<Object?>>[
      container.listen(nodesProvider, (_, __) {}),
      container.listen(ruleSetsProvider, (_, __) {}),
      container.listen(ruleSetDirectoryProvider, (_, __) {}),
    ];
    addTearDown(() {
      for (final handle in handles) {
        handle.close();
      }
    });
    await container.read(ruleSetsProvider.future);
    await container.read(ruleSetDirectoryProvider.future);
  }

  /// Builds the document the way the tunnel controller would.
  Result<CoreConfig, CommyFailure> build() {
    return container.read(configGeneratorProvider).build(
          node: testNode(),
          routing: harness.routingRepository.policy,
          dns: DnsSettings.defaults,
          settings: AppSettings.defaults,
          includeClashApi: false,
        );
  }

  test('without the file the rule is dropped, and said out loud', () async {
    await start(matchers: <String>['geosite:ru']);

    final config = build();

    expect(config.isOk, isTrue);
    expect(config.valueOrNull!.encode(), isNot(contains('geosite-ru')));
    expect(
      container.read(configWarningsProvider).join('\n'),
      contains('geosite-ru'),
    );
  });

  test('with the file the rule applies and the path points at it', () async {
    await start(matchers: <String>['geosite:ru']);
    await harness.ruleSetRepository.download(
      tag: 'geosite-ru',
      from: Uri.parse('https://mirror.example/geosite-ru.srs'),
    );
    await container.read(ruleSetsProvider.future);

    final document = build().valueOrNull!.encode();

    expect(document, contains('geosite-ru'));
    // The core loads this file itself, out of process, so the path in the
    // document has to be the directory the repository actually writes to.
    expect(
      document,
      contains('${FakeRuleSetRepository.path}/geosite-ru.srs'),
    );
    expect(container.read(configWarningsProvider), isEmpty);
  });

  test('deleting the file drops the rule again on the next build', () async {
    await start(matchers: <String>['geosite:ru']);
    await harness.ruleSetRepository.download(
      tag: 'geosite-ru',
      from: Uri.parse('https://mirror.example/geosite-ru.srs'),
    );
    await container.read(ruleSetsProvider.future);
    expect(build().valueOrNull!.encode(), contains('geosite-ru'));

    await harness.ruleSetRepository.delete('geosite-ru');
    await pumpEventQueue();

    expect(build().valueOrNull!.encode(), isNot(contains('geosite-ru')));
    expect(
      container.read(configWarningsProvider).join('\n'),
      contains('geosite-ru'),
    );
  });
}
