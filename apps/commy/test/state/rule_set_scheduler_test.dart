import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/rule_set_scheduler.dart';
import 'package:commy/src/state/subscription_scheduler.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/commy_test_app.dart';

/// Exceptions E-2 and E-3: a refresh on the interval the user set, off by
/// default, and never a first download. Every assertion is about which
/// requests were made — the only thing rule R1 cares about.
void main() {
  final ads = RouteSectionBuilder.adsRuleSetTag;
  final downloaded = DateTime.utc(2026, 9);

  late CommyTestHarness harness;
  late ProviderContainer container;
  late DateTime now;

  Future<RuleSetScheduler> start({
    AppSettings settings = const AppSettings(ruleSetUpdateDays: 7),
    List<RuleSet> onDisk = const <RuleSet>[],
    RoutingPolicy policy = const RoutingPolicy(blockAds: true),
  }) async {
    harness = CommyTestHarness(settings: settings, ruleSets: onDisk);
    await harness.routingRepository.write(policy);
    // What the scheduler reads with `.value` must have arrived first.
    container = ProviderContainer(
      overrides: harness.overrides(
        extra: [refreshClockProvider.overrideWithValue(() => now)],
      ),
    )
      ..listen(settingsProvider, (_, __) {})
      ..listen(routingPolicyProvider, (_, __) {})
      ..listen(ruleSetsProvider, (_, __) {});
    await container.read(settingsProvider.future);
    await container.read(routingPolicyProvider.future);
    await container.read(ruleSetsProvider.future);
    return container.read(ruleSetRefreshProvider);
  }

  RuleSet stored(String tag) =>
      RuleSet(tag: tag, sizeBytes: 1024, updatedAt: downloaded);

  setUp(() => now = DateTime.utc(2026, 9, 29));
  tearDown(() async {
    container.dispose();
    await harness.dispose();
  });

  test('off by default: nothing is fetched, however old the file', () async {
    final scheduler = await start(
      settings: AppSettings.defaults,
      onDisk: <RuleSet>[stored(ads)],
    );

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  test('a file older than the interval is fetched again, from the source',
      () async {
    final scheduler = await start(onDisk: <RuleSet>[stored(ads)]);

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, <Uri>[
      AppSettings.defaults.ruleSetUrl(ads)!,
    ]);
  });

  test('a file younger than the interval is left alone', () async {
    now = downloaded.add(const Duration(days: 6));
    final scheduler = await start(onDisk: <RuleSet>[stored(ads)]);

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  test('a rule set the rules need but the phone never downloaded is not '
      'fetched for the first time', () async {
    final scheduler = await start();

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  test('a file on disk that no rule needs is not kept up to date', () async {
    final scheduler = await start(
      onDisk: <RuleSet>[stored('geosite-cn')],
    );

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  test('no source, no refresh', () async {
    final scheduler = await start(
      settings: const AppSettings(ruleSetSource: '', ruleSetUpdateDays: 7),
      onDisk: <RuleSet>[stored(ads)],
    );

    await scheduler.sweep();

    expect(harness.ruleSetRepository.requests, isEmpty);
  });

  test('a source that failed is left alone for hours, then asked again',
      () async {
    final scheduler = await start(onDisk: <RuleSet>[stored(ads)]);
    harness.ruleSetRepository.failure = const StorageFailure('mirror down');

    await scheduler.sweep();
    now = now.add(const Duration(hours: 1));
    await scheduler.sweep();
    expect(harness.ruleSetRepository.requests, hasLength(1));

    now = now.add(RuleSetScheduler.retryAfterFailure);
    await scheduler.sweep();
    expect(harness.ruleSetRepository.requests, hasLength(2));
  });
}
