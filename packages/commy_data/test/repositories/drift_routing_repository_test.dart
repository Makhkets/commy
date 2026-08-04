import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_stack.dart';

const policy = RoutingPolicy(
  rules: <RoutingRule>[
    RoutingRule(id: 'r1', matcher: 'geosite:ru', action: RuleAction.direct),
    RoutingRule(
      id: 'r2',
      matcher: 'geoip:private',
      action: RuleAction.direct,
      sortIndex: 1,
    ),
    RoutingRule(
      id: 'r3',
      matcher: 'domain_suffix:ads.example',
      action: RuleAction.block,
      sortIndex: 2,
      enabled: false,
    ),
  ],
  perAppMode: PerAppMode.exclude,
  perAppPackages: <String>['com.example.bank'],
);

void main() {
  late TestStack stack;
  late DriftRoutingRepository repository;

  setUp(() {
    stack = TestStack.create();
    repository = stack.routing;
  });
  tearDown(() async {
    await stack.dispose();
  });

  group('DriftRoutingRepository routing', () {
    test('an empty database reads the defaults', () async {
      final read = (await repository.read()).valueOrNull;

      expect(read, equals(RoutingPolicy.defaults));
    });

    test('a policy round trips, rules and envelope together', () async {
      await repository.write(policy);

      final read = (await repository.read()).valueOrNull!;

      expect(read.mode, equals(RoutingMode.rules));
      expect(read.perAppMode, equals(PerAppMode.exclude));
      expect(read.perAppPackages, equals(<String>['com.example.bank']));
      expect(read.bypassLan, isTrue);
      expect(read.blockAds, isFalse);
      expect(read.rules, hasLength(3));
      expect(read.rules.first.matcher, equals('geosite:ru'));
      expect(read.activeRules, hasLength(2));
    });

    test('rules come back in sortIndex order', () async {
      await repository.write(policy);

      final read = (await repository.read()).valueOrNull!;
      final matchers = read.rules.map((rule) => rule.matcher).toList();

      expect(
        matchers,
        equals(<String>[
          'geosite:ru',
          'geoip:private',
          'domain_suffix:ads.example',
        ]),
      );
    });

    test('writing replaces the rule list wholesale', () async {
      await repository.write(policy);
      await repository.write(
        policy.copyWith(rules: const <RoutingRule>[]),
      );

      final read = (await repository.read()).valueOrNull!;

      expect(read.rules, isEmpty);
      expect(read.perAppMode, equals(PerAppMode.exclude));
    });

    test('watch emits the assembled policy', () async {
      await repository.write(policy);

      final emitted = await repository.watch().first;

      expect(emitted.rules, hasLength(3));
      expect(emitted.perAppMode, equals(PerAppMode.exclude));
    });

    test('an unknown mode in storage falls back to the default', () async {
      await stack.database.customStatement(
        'INSERT INTO settings (key, value_json) '
        """VALUES ('routing_policy', '{"mode":"telepathy"}')""",
      );

      final read = (await repository.read()).valueOrNull!;

      expect(read.mode, equals(RoutingPolicy.defaults.mode));
    });
  });

  group('DriftRoutingRepository dns', () {
    test('an empty database reads the defaults', () async {
      final read = (await repository.readDns()).valueOrNull;

      expect(read, equals(DnsSettings.defaults));
    });

    test('dns settings round trip', () async {
      const dns = DnsSettings(
        remote: 'https://dns.example.com/dns-query',
        strategy: DnsStrategy.ipv4Only,
        fakeIp: true,
      );
      await repository.writeDns(dns);

      expect((await repository.readDns()).valueOrNull, equals(dns));
    });

    test('watchDns emits the current settings', () async {
      await repository.writeDns(
        const DnsSettings(strategy: DnsStrategy.preferIpv6),
      );

      final emitted = await repository.watchDns().first;

      expect(emitted.strategy, equals(DnsStrategy.preferIpv6));
    });
  });
}
