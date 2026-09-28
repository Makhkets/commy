import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/test_stack.dart';

/// A backup made on one phone and restored on another, through the real
/// repositories, the real cipher and the real library store — the only fakes
/// are two in-memory databases and two in-memory keystores.
void main() {
  late TestStack phoneA;
  late TestStack phoneB;
  final cipher =
      PasswordBackupCipher(memoryKiB: 64, iterations: 1, parallelism: 1);

  // What the database holds, table by table: either it travels in a backup,
  // or there is a reason it does not. A table added later fails here until
  // someone decides which — otherwise it is left out of every backup
  // without anybody having chosen that.
  const inBackup = <String>{
    'subscriptions',
    'node_groups',
    'nodes',
    'routing_rules',
    'settings',
  };
  const leftOut = <String, String>{
    'traffic_daily': 'what happened on this phone, not a choice anyone made',
    'import_failures': 'transient and already redacted',
  };

  ExportBackupUseCase exportFrom(TestStack phone) => ExportBackupUseCase(
        library:
            DriftLibraryStore(database: phone.database, secrets: phone.vault),
        settings: phone.settings,
        routing: phone.routing,
        ruleSets: _NoRuleSets(),
        cipher: cipher,
        appVersion: 'test',
        platform: 'android',
      );

  RestoreBackupUseCase restoreInto(TestStack phone) => RestoreBackupUseCase(
        library:
            DriftLibraryStore(database: phone.database, secrets: phone.vault),
        settings: phone.settings,
        routing: phone.routing,
        ruleSets: _NoRuleSets(),
        platform: 'android',
        requiredRuleSets: (_) => const <String>[],
      );

  setUp(() async {
    phoneA = TestStack.create();
    phoneB = TestStack.create();
    await phoneA.subscriptions.upsert(Fixtures.subscription());
    await phoneA.nodes.upsertGroup(const NodeGroup(id: 'g1', name: 'Work'));
    await phoneA.nodes.upsertAll(<ProxyNode>[
      Fixtures.vlessNode(subscriptionId: 'sub-1'),
      Fixtures.trojanNode().copyWith(groupId: 'g1'),
    ]);
    await phoneA.routing.write(
      const RoutingPolicy(
        rules: <RoutingRule>[
          RoutingRule(
            id: 'r1',
            matcher: 'domain_suffix:ru',
            action: RuleAction.direct,
          ),
          RoutingRule(
            id: 'r2',
            matcher: 'domain:example.org',
            action: RuleAction.block,
            sortIndex: 1,
          ),
          RoutingRule(
            id: 'r3',
            matcher: 'ip_cidr:10.0.0.0/8',
            action: RuleAction.proxy,
            sortIndex: 2,
            enabled: false,
          ),
        ],
        blockAds: true,
      ),
    );
    await phoneA.routing.writeDns(const DnsSettings(fakeIp: true));
    await phoneA.settings.write(const AppSettings(hideUnavailable: true));
    await phoneA.settings.writeSelectedNodeId('node-trojan');
    await phoneA.store.write(SecretKeys.deviceId, 'hwid-of-phone-a');
    await phoneB.store.write(SecretKeys.deviceId, 'hwid-of-phone-b');
  });
  tearDown(() async {
    await phoneA.dispose();
    await phoneB.dispose();
  });

  test('every table is either in a backup or left out on purpose', () {
    final tables =
        phoneA.database.allTables.map((t) => t.actualTableName).toSet();

    expect(tables, <String>{...inBackup, ...leftOut.keys});
  });

  test('every settings key travels', () {
    // All four are the user's choices; a fifth needs a decision here.
    expect(SettingKeys.all.toSet(), <String>{
      SettingKeys.appSettings,
      SettingKeys.routingPolicy,
      SettingKeys.dnsSettings,
      SettingKeys.selectedNodeId,
    });
  });

  test('what phone A had, phone B has — and phone B keeps its own id',
      () async {
    final sealed =
        (await exportFrom(phoneA)('a long password')).valueOrNull!.bytes;
    final opened = (await ReadBackupUseCase(cipher: cipher)(
      sealed,
      'a long password',
    ))
        .valueOrNull!;
    final restored = await restoreInto(phoneB)(opened);

    expect(restored.isOk, isTrue);
    final subscriptions = (await phoneB.subscriptions.getAll()).valueOrNull!;
    expect(subscriptions.single.url, Fixtures.subscriptionUrl);
    final nodes = (await phoneB.nodes.getAll()).valueOrNull!;
    expect(
      nodes.map((n) => n.id).toSet(),
      <String>{'node-vless', 'node-trojan'},
    );
    expect(
      nodes.firstWhere((n) => n.id == 'node-vless').param('uuid'),
      Fixtures.uuid,
    );
    expect(
      nodes.firstWhere((n) => n.id == 'node-trojan').param('password'),
      Fixtures.password,
    );
    expect((await phoneB.nodes.watchGroups().first).single.name, 'Work');
    final policy = (await phoneB.routing.read()).valueOrNull!;
    // In the order the user put them, the switched-off one still off.
    expect(policy.rules.map((r) => r.id), <String>['r1', 'r2', 'r3']);
    expect(policy.rules.last.enabled, isFalse);
    expect(nodes.firstWhere((n) => n.id == 'node-trojan').groupId, 'g1');
    expect(policy.blockAds, isTrue);
    expect((await phoneB.routing.readDns()).valueOrNull!.fakeIp, isTrue);
    expect(
      (await phoneB.settings.read()).valueOrNull!.hideUnavailable,
      isTrue,
    );
    expect(
      (await phoneB.settings.readSelectedNodeId()).valueOrNull,
      'node-trojan',
    );
    // An installation id names the installation (ADR-0009).
    expect(phoneB.store.snapshot[SecretKeys.deviceId], 'hwid-of-phone-b');
  });

  test('the backup never holds the installation id', () async {
    final sealed =
        (await exportFrom(phoneA)('a long password')).valueOrNull!.bytes;
    final plain = (await cipher.open(sealed, 'a long password')).valueOrNull!;

    expect(String.fromCharCodes(plain), isNot(contains('hwid-of-phone-a')));
  });
}

class _NoRuleSets implements RuleSetRepository {
  @override
  Stream<List<RuleSet>> watch() =>
      Stream<List<RuleSet>>.value(const <RuleSet>[]);

  @override
  Future<Result<List<RuleSet>, CommyFailure>> list() async =>
      const Ok<List<RuleSet>, CommyFailure>(<RuleSet>[]);

  @override
  Future<Result<String, CommyFailure>> directory() async =>
      const Ok<String, CommyFailure>('/nowhere');

  @override
  Future<Result<RuleSet, CommyFailure>> download({
    required String tag,
    required Uri from,
  }) =>
      throw UnimplementedError('a backup never downloads');

  @override
  Future<Result<void, CommyFailure>> delete(String tag) async =>
      const Ok<void, CommyFailure>(null);
}
