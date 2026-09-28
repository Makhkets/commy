import 'dart:convert';
import 'dart:typed_data';

import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/backup_fakes.dart';

const _password = 'long enough';

final _subscription = Subscription(
  id: 'sub-1',
  name: 'Panel',
  url: Uri.parse('https://panel.example.com/sub/TOKEN0123456789'),
);

const _server = ProxyNode(
  id: 'a1b2c3d4e5f60718',
  name: 'Finland',
  protocol: Protocol.vless,
  host: 'fi.example.com',
  port: 443,
  subscriptionId: 'sub-1',
  params: <String, Object?>{'uuid': '8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88'},
);

void main() {
  group('ExportBackupUseCase', () {
    late RecordingLibraryStore library;
    late MemorySettingsRepository settings;
    late MemoryRoutingRepository routing;
    late PasswordPrefixCipher cipher;

    ExportBackupUseCase useCase() => ExportBackupUseCase(
          library: library,
          settings: settings,
          routing: routing,
          ruleSets: MemoryRuleSetRepository(<String>['geosite-ru']),
          cipher: cipher,
          appVersion: '0.1.0-alpha.10',
          platform: 'android',
          now: () => DateTime.utc(2026, 9, 29, 12),
        );

    setUp(() async {
      library = RecordingLibraryStore()
        ..contents = (
          subscriptions: <Subscription>[_subscription],
          groups: const <NodeGroup>[],
          nodes: const <ProxyNode>[_server],
        );
      settings = MemorySettingsRepository()
        ..settings = const AppSettings(autoConnect: true)
        ..selected = _server.id;
      routing = MemoryRoutingRepository()
        ..policy = const RoutingPolicy(mode: RoutingMode.global);
      cipher = PasswordPrefixCipher();
    });

    test('everything the user set up goes in, sealed under the password',
        () async {
      final result = await useCase()(_password);

      final value = result.valueOrNull!;
      expect(utf8.decode(value.bytes).startsWith('$_password|'), isTrue);
      final json = jsonDecode(cipher.lastPlain!) as Map<String, Object?>;
      expect(json['format'], BackupSnapshot.format);
      expect(json['schema'], BackupSnapshot.schema);
      expect(json['createdAt'], '2026-09-29T12:00:00.000Z');
      expect(json['platform'], 'android');
      expect(json['selectedNodeId'], _server.id);
      expect(json['ruleSets'], <String>['geosite-ru']);
      final snapshot = value.snapshot;
      expect(snapshot.subscriptions.single.url, _subscription.url);
      expect(snapshot.nodes.single.param('uuid'), _server.param('uuid'));
      expect(snapshot.settings!.autoConnect, isTrue);
      expect(snapshot.routing!.mode, RoutingMode.global);
    });

    test('a short password seals nothing', () async {
      final result = await useCase()('short');

      expect(result.isErr, isTrue);
      expect(cipher.lastPlain, isNull);
    });

    test('a store that fails fails the export', () async {
      routing.readFailure = const StorageFailure('disk');

      final result = await useCase()(_password);

      expect(result.failureOrNull, const StorageFailure('disk'));
      expect(cipher.lastPlain, isNull);
    });

    test('an unreadable keystore fails the export instead of dropping keys',
        () async {
      library.readFailure = const StorageFailure('keystore locked');

      final result = await useCase()(_password);

      expect(result.failureOrNull, const StorageFailure('keystore locked'));
      expect(cipher.lastPlain, isNull);
    });

    test('a cipher that fails fails the export', () async {
      cipher.failure = const StorageFailure('no isolate');

      expect(
        (await useCase()(_password)).failureOrNull,
        const StorageFailure('no isolate'),
      );
    });
  });

  group('ReadBackupUseCase', () {
    final cipher = PasswordPrefixCipher();
    final read = ReadBackupUseCase(cipher: cipher);

    String payload({int schema = BackupSnapshot.schema}) => jsonEncode(
          BackupSnapshot(
            createdAt: DateTime.utc(2026, 9, 29),
            appVersion: 'x',
            platform: 'android',
            subscriptions: <Subscription>[_subscription],
            nodes: const <ProxyNode>[_server],
          ).toJson()
            ..['schema'] = schema,
        );

    test('the right password gives back the snapshot', () async {
      final result = await read(
        PasswordPrefixCipher.fileOf(_password, payload()),
        _password,
      );

      expect(result.valueOrNull!.nodes.single.id, _server.id);
    });

    test("a wrong password is the cipher's answer, passed on", () async {
      final result = await read(
        PasswordPrefixCipher.fileOf(_password, payload()),
        'another one',
      );

      expect(
        result.failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('a payload from a newer Commy asks for an update', () async {
      final result = await read(
        PasswordPrefixCipher.fileOf(
          _password,
          payload(schema: BackupSnapshot.schema + 1),
        ),
        _password,
      );

      expect(
        result.failureOrNull,
        const BackupFailure(BackupProblem.newerVersion),
      );
    });

    test('opened but not a snapshot is unreadable', () async {
      for (final inside in <String>['not json', '[1,2]', '{"a":1}']) {
        final result = await read(
          PasswordPrefixCipher.fileOf(_password, inside),
          _password,
        );

        expect(
          result.failureOrNull,
          const BackupFailure(BackupProblem.unreadable),
          reason: inside,
        );
      }
    });

    test('invalid UTF-8 inside is unreadable, not a crash', () async {
      final file = Uint8List.fromList(
        <int>[...utf8.encode('$_password|'), 0xff, 0xfe, 0xfd],
      );

      expect(
        (await read(file, _password)).failureOrNull,
        const BackupFailure(BackupProblem.unreadable),
      );
    });
  });

  group('RestoreBackupUseCase', () {
    late RecordingLibraryStore library;
    late MemorySettingsRepository settings;
    late MemoryRoutingRepository routing;

    RestoreBackupUseCase useCase({
      String platform = 'android',
      List<String> present = const <String>[],
    }) =>
        RestoreBackupUseCase(
          library: library,
          settings: settings,
          routing: routing,
          ruleSets: MemoryRuleSetRepository(present),
          platform: platform,
          // Stands in for RouteSectionBuilder: one set per rule matcher.
          requiredRuleSets: (routing) => <String>[
            for (final rule in routing.rules) rule.matcher,
          ],
        );

    BackupSnapshot snapshot({
      String platform = 'android',
      RoutingPolicy? policy = const RoutingPolicy(
        rules: <RoutingRule>[
          RoutingRule(
            id: 'r1',
            matcher: 'geosite-ru',
            action: RuleAction.direct,
          ),
          RoutingRule(
            id: 'r2',
            matcher: 'geosite-category-ads-all',
            action: RuleAction.block,
          ),
        ],
        perAppMode: PerAppMode.include,
        perAppPackages: <String>['org.browser'],
      ),
      AppSettings? appSettings = const AppSettings(autoConnect: true),
      DnsSettings? dns = const DnsSettings(fakeIp: true),
    }) =>
        BackupSnapshot(
          createdAt: DateTime.utc(2026, 9, 29),
          appVersion: 'x',
          platform: platform,
          subscriptions: <Subscription>[_subscription],
          nodes: const <ProxyNode>[_server],
          routing: policy,
          dns: dns,
          settings: appSettings,
          selectedNodeId: _server.id,
          ruleSets: const <String>['geosite-ru', 'geosite-category-ads-all'],
        );

    setUp(() {
      library = RecordingLibraryStore();
      settings = MemorySettingsRepository()..selected = 'old-server';
      routing = MemoryRoutingRepository();
    });

    test('the library, routing, DNS, settings and selection are replaced',
        () async {
      final result = await useCase()(snapshot());

      expect(result.isOk, isTrue);
      expect(library.subscriptions, <Subscription>[_subscription]);
      expect(library.nodes, const <ProxyNode>[_server]);
      expect(routing.policy.perAppPackages, <String>['org.browser']);
      expect(routing.dns.fakeIp, isTrue);
      expect(settings.settings.autoConnect, isTrue);
      expect(settings.selected, _server.id);
      expect(result.valueOrNull!.perAppDropped, isFalse);
    });

    test('rule sets the restored rules need and this phone lacks are named',
        () async {
      final result = await useCase(present: <String>['geosite-ru'])(snapshot());

      expect(
        result.valueOrNull!.missingRuleSets,
        <String>['geosite-category-ads-all'],
      );
    });

    test("another platform's app list is dropped, and the user is told",
        () async {
      final result = await useCase(platform: 'windows')(snapshot());

      expect(routing.policy.perAppMode, PerAppMode.disabled);
      expect(routing.policy.perAppPackages, isEmpty);
      expect(result.valueOrNull!.perAppDropped, isTrue);
    });

    test('an app list that is already off is not reported as dropped',
        () async {
      final result = await useCase(platform: 'windows')(
        snapshot(policy: RoutingPolicy.defaults),
      );

      expect(result.valueOrNull!.perAppDropped, isFalse);
    });

    test('a section that did not parse leaves what this phone has', () async {
      settings.settings = const AppSettings(hideUnavailable: true);

      await useCase()(snapshot(appSettings: null, policy: null, dns: null));

      expect(settings.writes, 0);
      expect(routing.writes, 0);
      expect(settings.settings.hideUnavailable, isTrue);
    });

    test('the old selection goes with the old library', () async {
      final empty = BackupSnapshot(
        createdAt: DateTime.utc(2026, 9, 29),
        appVersion: 'x',
        platform: 'android',
      );

      await useCase()(empty);

      expect(settings.selected, isNull);
    });

    test('a later step that fails leaves the selection pointing at the backup',
        () async {
      routing.writeFailure = const StorageFailure('disk full');

      final result = await useCase()(snapshot());

      expect(result.failureOrNull, const StorageFailure('disk full'));
      // Not at 'old-server', which the library replace already removed.
      expect(settings.selected, _server.id);
    });

    test('a library that cannot be replaced changes nothing else', () async {
      library.failure = const StorageFailure('keystore');

      final result = await useCase()(snapshot());

      expect(result.failureOrNull, const StorageFailure('keystore'));
      expect(routing.writes, 0);
      expect(settings.writes, 0);
      expect(settings.selected, 'old-server');
    });
  });
}
