import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

final _subscription = Subscription(
  id: 'sub-1',
  name: 'Panel',
  url: Uri.parse('https://panel.example.com/sub/TOKEN0123456789'),
  autoUpdate: true,
  lastUpdatedAt: DateTime.utc(2026, 9, 20, 10),
);

final _server = ProxyNode(
  id: 'a1b2c3d4e5f60718',
  name: 'Finland',
  protocol: Protocol.vless,
  host: 'fi.example.com',
  port: 443,
  subscriptionId: 'sub-1',
  countryCode: 'FI',
  latency: const Duration(milliseconds: 124),
  lastCheckedAt: DateTime.utc(2026, 9, 28),
  sortIndex: 3,
  params: const <String, Object?>{
    'uuid': '8f3c1e6a-9d2b-4c7f-a1e5-0b6d4a2c9f88',
    'sni': 'www.microsoft.com',
    'sid': '7f3a2b1c',
  },
);

const _manual = ProxyNode(
  id: 'ffeeddccbbaa9988',
  name: 'My own',
  protocol: Protocol.trojan,
  host: 'mine.example.org',
  port: 8443,
  params: <String, Object?>{'password': 'hunter2-hunter2'},
);

BackupSnapshot _snapshot() => BackupSnapshot(
      createdAt: DateTime.utc(2026, 9, 29, 12),
      appVersion: '0.1.0-alpha.10',
      platform: 'android',
      subscriptions: <Subscription>[_subscription],
      nodes: <ProxyNode>[_server, _manual],
      routing: const RoutingPolicy(
        rules: <RoutingRule>[
          RoutingRule(
            id: 'r1',
            matcher: 'domain_suffix:ru',
            action: RuleAction.direct,
          ),
        ],
        perAppMode: PerAppMode.exclude,
        perAppPackages: <String>['org.bank'],
      ),
      dns: const DnsSettings(fakeIp: true),
      settings: const AppSettings(autoConnect: true, sendDeviceId: false),
      selectedNodeId: _manual.id,
      ruleSets: const <String>['geosite-category-ads-all'],
    );

/// Through JSON text and back, as the file does it.
BackupSnapshot _roundTrip(BackupSnapshot snapshot) => BackupSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>,
    );

Map<String, Object?> _json() =>
    jsonDecode(jsonEncode(_snapshot().toJson())) as Map<String, Object?>;

void main() {
  group('BackupSnapshot', () {
    test('everything the user set up survives the trip through JSON', () {
      final back = _roundTrip(_snapshot());

      expect(back.subscriptions.single.url, _subscription.url);
      expect(back.subscriptions.single.autoUpdate, isTrue);
      expect(back.nodes.map((n) => n.id), <String>[_server.id, _manual.id]);
      expect(back.nodes.first.params, _server.params);
      expect(back.nodes.first.subscriptionId, 'sub-1');
      expect(back.nodes.first.sortIndex, 3);
      expect(back.nodes.last.param('password'), 'hunter2-hunter2');
      expect(back.routing, _snapshot().routing);
      expect(back.dns, _snapshot().dns);
      expect(back.settings, _snapshot().settings);
      expect(back.selectedNodeId, _manual.id);
      expect(back.ruleSets, <String>['geosite-category-ads-all']);
      expect(back.appVersion, '0.1.0-alpha.10');
      expect(back.platform, 'android');
      expect(back.skipped, 0);
    });

    test('latency measured on another network is left behind', () {
      final json = _json();
      final server = (json['nodes']! as List<Object?>).first! as Map;

      expect(server.containsKey('latencyMicros'), isFalse);
      expect(server.containsKey('lastCheckedAt'), isFalse);
      expect(_roundTrip(_snapshot()).nodes.first.latency, isNull);
    });

    test('times are written in UTC', () {
      final local = BackupSnapshot(
        createdAt: DateTime(2026, 9, 29, 15),
        appVersion: '',
        platform: 'android',
      );

      expect(
        (local.toJson()['createdAt']! as String).endsWith('Z'),
        isTrue,
      );
      final subscription =
          (_json()['subscriptions']! as List<Object?>).single! as Map;
      expect((subscription['lastUpdatedAt']! as String).endsWith('Z'), isTrue);
    });

    test('the manual count leaves subscription servers out', () {
      expect(_snapshot().manualNodeCount, 1);
    });

    test('a server this version does not understand is skipped, not fatal', () {
      final json = _json();
      final nodes = json['nodes']! as List<Object?>;
      (nodes.first! as Map<String, Object?>)['protocol'] = 'quantum';

      final back = BackupSnapshot.fromJson(json);

      expect(back.nodes.map((n) => n.id), <String>[_manual.id]);
      expect(back.skipped, 1);
      expect(back.subscriptions, hasLength(1));
    });

    test('a server whose subscription is missing becomes a server of its own',
        () {
      final json = _json()..['subscriptions'] = <Object?>[];

      final back = BackupSnapshot.fromJson(json);

      expect(back.nodes.first.subscriptionId, isNull);
      expect(back.manualNodeCount, 2);
    });

    test('a server in a group that is missing loses the group, not itself', () {
      final json = _json();
      ((json['nodes']! as List<Object?>).last!
          as Map<String, Object?>)['groupId'] = 'gone';

      expect(BackupSnapshot.fromJson(json).nodes.last.groupId, isNull);
    });

    test('one rule this version cannot read costs that rule, not the list', () {
      final json = _json();
      final routing = json['routing']! as Map<String, Object?>;
      (routing['rules']! as List<Object?>).add(<String, Object?>{
        'id': 'r2',
        'matcher': 'domain:example.org',
        'action': 'teleport',
      });

      final back = BackupSnapshot.fromJson(json);

      expect(back.routing!.rules.map((r) => r.id), <String>['r1']);
      expect(back.routing!.perAppPackages, <String>['org.bank']);
      expect(back.skipped, 1);
    });

    test('a repeated id keeps the first and counts the second', () {
      final json = _json();
      final nodes = json['nodes']! as List<Object?>;
      nodes.add(nodes.first);

      final back = BackupSnapshot.fromJson(json);

      expect(back.nodes, hasLength(2));
      expect(back.skipped, 1);
    });

    test('a selection naming a server not in the file is dropped', () {
      final json = _json()..['selectedNodeId'] = 'not-in-file';

      expect(BackupSnapshot.fromJson(json).selectedNodeId, isNull);
    });

    test('settings from a newer Commy come back null: keep what is here', () {
      final json = _json();
      (json['settings']! as Map<String, Object?>)['themeMode'] = 'sepia';

      final back = BackupSnapshot.fromJson(json);

      expect(back.settings, isNull);
      expect(back.routing, isNotNull);
      expect(back.nodes, hasLength(2));
    });

    test('schemaOf tells a backup payload from anything else', () {
      expect(BackupSnapshot.schemaOf(_json()), BackupSnapshot.schema);
      expect(BackupSnapshot.schemaOf(<String, Object?>{'schema': 1}), isNull);
      expect(
        BackupSnapshot.schemaOf(<String, Object?>{
          'format': BackupSnapshot.format,
          'schema': '1',
        }),
        isNull,
      );
    });

    test('a payload from a newer schema or not a payload at all throws', () {
      expect(
        () => BackupSnapshot.fromJson(
          _json()..['schema'] = BackupSnapshot.schema + 1,
        ),
        throwsFormatException,
      );
      expect(
        () => BackupSnapshot.fromJson(<String, Object?>{'a': 1}),
        throwsFormatException,
      );
      expect(
        () => BackupSnapshot.fromJson(_json()..remove('createdAt')),
        throwsFormatException,
      );
    });
  });
}
