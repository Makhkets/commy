import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

ProxyNode buildNode() => const ProxyNode(
      id: 'n1',
      name: 'Amsterdam 03',
      protocol: Protocol.vless,
      host: '203.0.113.10',
      port: 443,
      subscriptionId: 'sub1',
      countryCode: 'NL',
      sortIndex: 2,
      params: <String, Object?>{
        'uuid': '11111111-2222-3333-4444-555555555555',
        'password': 'hunter2',
        'sid': 'a1b2c3',
        'privateKey': 'kOAbC',
        'flow': 'xtls-rprx-vision',
        'security': 'reality',
        'sni': 'www.microsoft.com',
        'pbk': 'publicRealityKey',
        'fp': 'chrome',
      },
    );

void main() {
  group('ProxyNode.redacted (rule R3)', () {
    test('blanks every secret parameter and keeps the rest', () {
      final safe = buildNode().redacted();

      expect(safe.params['uuid'], '[redacted]');
      expect(safe.params['password'], '[redacted]');
      expect(safe.params['sid'], '[redacted]');
      expect(safe.params['privateKey'], '[redacted]');

      expect(safe.params['flow'], 'xtls-rprx-vision');
      expect(safe.params['security'], 'reality');
      expect(safe.params['sni'], 'www.microsoft.com');
      expect(safe.params['pbk'], 'publicRealityKey');
      expect(safe.params['fp'], 'chrome');
    });

    test('no secret value survives anywhere in the redacted map', () {
      final safe = buildNode().redacted();
      final rendered = safe.params.values.join(' ');

      for (final secret in <String>[
        '11111111-2222-3333-4444-555555555555',
        'hunter2',
        'a1b2c3',
        'kOAbC',
      ]) {
        expect(rendered, isNot(contains(secret)));
      }
    });

    test('matches secret keys regardless of case', () {
      const node = ProxyNode(
        id: 'n2',
        name: 'x',
        protocol: Protocol.vmess,
        host: 'example.org',
        port: 80,
        params: <String, Object?>{'UUID': 'abc', 'Password': 'def'},
      );

      final safe = node.redacted();

      expect(safe.params['UUID'], '[redacted]');
      expect(safe.params['Password'], '[redacted]');
    });

    test('leaves everything outside params alone', () {
      final node = buildNode();
      final safe = node.redacted();

      expect(safe.id, node.id);
      expect(safe.name, node.name);
      expect(safe.host, node.host);
      expect(safe.port, node.port);
      expect(safe.protocol, node.protocol);
    });

    test('toString never prints params', () {
      expect(buildNode().toString(), isNot(contains('hunter2')));
      expect(buildNode().toString(), contains('203.0.113.10'));
    });
  });

  group('ProxyNode.copyWith', () {
    test('an omitted argument keeps the current value', () {
      final node = buildNode();
      final copy = node.copyWith(name: 'Renamed');

      expect(copy.name, 'Renamed');
      expect(copy.subscriptionId, 'sub1');
      expect(copy.countryCode, 'NL');
      expect(copy.sortIndex, 2);
    });

    test('an explicit null clears a nullable field', () {
      final node = buildNode();
      final copy = node.copyWith(subscriptionId: null);

      expect(copy.subscriptionId, isNull);
      expect(copy.countryCode, 'NL');
      expect(node.subscriptionId, 'sub1');
    });

    test('latency can be set and cleared', () {
      final node = buildNode();
      final measured = node.copyWith(latency: const Duration(milliseconds: 48));
      final cleared = measured.copyWith(latency: null);

      expect(measured.latency, const Duration(milliseconds: 48));
      expect(cleared.latency, isNull);
    });
  });

  group('ProxyNode JSON', () {
    test('survives a round trip unchanged', () {
      final node = buildNode().copyWith(
        latency: const Duration(milliseconds: 48),
        lastCheckedAt: DateTime.utc(2026, 8, 4, 12, 30),
      );

      final restored = ProxyNode.fromJson(node.toJson());

      expect(restored, equals(node));
      expect(restored.hashCode, node.hashCode);
    });

    test('tolerates a missing optional block', () {
      final restored = ProxyNode.fromJson(<String, Object?>{
        'id': 'n3',
        'name': 'Bare',
        'protocol': 'trojan',
        'host': 'example.net',
        'port': 8443,
      });

      expect(restored.protocol, Protocol.trojan);
      expect(restored.sortIndex, 0);
      expect(restored.params, isEmpty);
      expect(restored.latency, isNull);
    });
  });

  group('ProxyNode helpers', () {
    test('param reads a value as a string', () {
      expect(buildNode().param('fp'), 'chrome');
      expect(buildNode().param('nope'), isNull);
    });

    test('isFromSubscription tells the two sources apart', () {
      expect(buildNode().isFromSubscription, isTrue);
      expect(
        buildNode().copyWith(subscriptionId: null).isFromSubscription,
        isFalse,
      );
    });
  });

  group('Protocol', () {
    test('fromScheme accepts the aliases real links use', () {
      expect(Protocol.fromScheme('vless'), Protocol.vless);
      expect(Protocol.fromScheme('VLESS://'), Protocol.vless);
      expect(Protocol.fromScheme('ss'), Protocol.shadowsocks);
      expect(Protocol.fromScheme('hy2'), Protocol.hysteria2);
      expect(Protocol.fromScheme('socks5'), Protocol.socks);
      expect(Protocol.fromScheme('ftp'), isNull);
      expect(Protocol.fromScheme(''), isNull);
    });

    test('every protocol has a distinct wire name', () {
      final names = Protocol.values.map((p) => p.wireName).toList();

      expect(names.toSet().length, names.length);
      expect(Protocol.shadowsocks.wireName, 'shadowsocks');
      expect(Protocol.shadowsocks.canonicalScheme, 'ss');
    });
  });
}
