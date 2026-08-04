import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Rule R3, tested the way docs/09-security-privacy.md asks for it:
///
/// > Тест обязателен: набор строк с кредами прогоняется через редактор и
/// > проверяется на отсутствие каждого секрета. Добавили новый тип секрета —
/// > добавили строку в тест.
///
/// Every case below is a line shaped like something the sing-box core or our
/// own HTTP layer actually writes.
void main() {
  const redactor = LogRedactor();

  group('LogRedactor.redact', () {
    test('removes a bare uuid', () {
      const line = 'outbound/vless[proxy]: using ${Fixtures.uuid}';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, contains(Redact.placeholder));
      expect(result, contains('outbound/vless[proxy]'));
    });

    test('removes credentials from a vless link but keeps the node name', () {
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443?security=reality&sid=${Fixtures.shortId}'
          '&fp=chrome#Frankfurt';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, isNot(contains(Fixtures.shortId)));
      expect(result, contains('de1.vpn.example.com:443'));
      expect(result, contains('#Frankfurt'));
    });

    test('removes the token from a subscription URL', () {
      final line = 'GET ${Fixtures.subscriptionUrl} -> 200';
      final result = redactor.redact(line);

      expect(result, isNot(contains('9f8e7d6c5b4a32100fedcba987654321')));
      expect(result, contains('https://panel.example.com/'));
    });

    test('keeps a bare origin readable', () {
      const line = 'dns: forwarding to tls://1.1.1.1';

      expect(redactor.redact(line), contains('tls://1.1.1.1'));
    });

    test('removes shadowsocks userinfo', () {
      // One ss:// link split across two source lines, not two words. A space
      // would change the fixture the redactor is being tested against.
      // ignore: missing_whitespace_between_adjacent_strings
      const line = 'import ss://YWVzLTI1Ni1nY206c3VwZXJzZWNyZXQ'
          '@1.2.3.4:8388#Node';
      final result = redactor.redact(line);

      expect(result, isNot(contains('YWVzLTI1Ni1nY206c3VwZXJzZWNyZXQ')));
      expect(result, contains('1.2.3.4:8388'));
    });

    test('removes a password field', () {
      const line = 'trojan: dial with password=${Fixtures.password} sni=x';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.password)));
      expect(result, contains('sni=x'));
    });

    test('removes a private key field', () {
      const line = 'wireguard: private_key=${Fixtures.privateKey}';

      expect(
        redactor.redact(line),
        isNot(contains(Fixtures.privateKey)),
      );
    });

    test('removes camelCase credential keys', () {
      const line = 'peerPublicKey: ${Fixtures.privateKey}, '
          'preSharedKey: ${Fixtures.shortId}';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.privateKey)));
      expect(result, isNot(contains(Fixtures.shortId)));
    });

    test('removes credentials out of a JSON fragment', () {
      const line = '{"id":"${Fixtures.uuid}","aid":0,'
          '"password":"${Fixtures.password}"}';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, isNot(contains(Fixtures.password)));
    });

    test('removes an Authorization header', () {
      const token = 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def';
      const line = 'Authorization: $token';
      final result = redactor.redact(line);

      expect(result, isNot(contains(token)));
      expect(result, contains('Authorization: ${Redact.placeholder}'));
    });

    test('keeps a short numeric id, which is not a secret', () {
      const line = 'connection id=42 closed';

      expect(redactor.redact(line), contains('id=42'));
    });

    test('removes a long opaque id, which might be', () {
      const opaque = 'Zm9vYmFyYmF6cXV1eHF1dXg';
      const line = 'inbound: id=$opaque';

      expect(redactor.redact(line), isNot(contains(opaque)));
    });

    test('leaves a line with nothing to hide alone', () {
      const line = 'router: matched rule geosite:ru -> direct';

      expect(redactor.redact(line), equals(line));
    });

    test('keeps the server address in the live view', () {
      const line = 'outbound: connecting to de1.vpn.example.com:443';

      expect(redactor.redact(line), contains('de1.vpn.example.com'));
    });
  });

  group('LogRedactor.redactForExport', () {
    test('replaces the user own server with a placeholder', () {
      final exporter = LogRedactor(
        serverHosts: () => <String>['de1.vpn.example.com', '1.2.3.4'],
      );
      const line = 'outbound: connecting to de1.vpn.example.com:443';
      final result = exporter.redactForExport(line);

      expect(result, isNot(contains('de1.vpn.example.com')));
      expect(result, contains(Redact.serverPlaceholder));
    });

    test('replaces the longest matching host first', () {
      final exporter = LogRedactor(
        serverHosts: () => <String>['example.com', 'de1.vpn.example.com'],
      );
      const line = 'dial de1.vpn.example.com';

      expect(
        exporter.redactForExport(line),
        equals('dial ${Redact.serverPlaceholder}'),
      );
    });

    test('still removes credentials', () {
      final exporter = LogRedactor(
        serverHosts: () => <String>['de1.vpn.example.com'],
      );
      const line = 'vless://${Fixtures.uuid}@de1.vpn.example.com:443';
      final result = exporter.redactForExport(line);

      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, isNot(contains('de1.vpn.example.com')));
    });
  });

  group('LogRedactor.redactLine', () {
    test('rewrites only the message', () {
      final at = DateTime.utc(2026, 8, 4, 12, 30);
      final line = LogLine(
        level: LogLevel.warn,
        message: 'uuid=${Fixtures.uuid}',
        at: at,
        tag: 'outbound',
      );
      final result = const LogRedactor().redactLine(line, forExport: false);

      expect(result.level, equals(LogLevel.warn));
      expect(result.at, equals(at));
      expect(result.tag, equals('outbound'));
      expect(result.message, isNot(contains(Fixtures.uuid)));
    });
  });
}
