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

    test('shows the node name the way the user typed it, not escaped', () {
      // The fragment is the one part of a link that survives redaction, and it
      // survives so a human can read it. `%20` reaching the logs screen undoes
      // the only reason it is there.
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443#Amsterdam%2003';

      expect(redactor.redact(line), contains('#Amsterdam 03'));
    });

    test('shows a name that is a flag and a non-Latin word', () {
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443'
          '#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt%20%E2%80%94%20%D0%BE%D1%81'
          '%D0%BD%D0%BE%D0%B2%D0%BD%D0%BE%D0%B9';

      expect(
        redactor.redact(line),
        contains('#\u{1F1E9}\u{1F1EA} Frankfurt — основной'),
      );
    });

    test('reads a node name the same way an import error does', () {
      // The logs screen and the import sheet quote the same link. Two answers
      // to "what is this node called" is a bug in one of them, so the log is
      // pinned to `Redact.link`, which is what the import path calls.
      const link = 'vless://${Fixtures.uuid}@de1.vpn.example.com:443'
          '?security=reality&sid=${Fixtures.shortId}#Amsterdam%2003';
      const line = 'failed to parse $link';

      final fromLog = redactor.redact(line);
      final fromImport = Redact.link(link);
      final name = fromImport.substring(fromImport.indexOf('#'));

      expect(fromLog, contains(name));
    });

    test('a credential smuggled into the node name stays redacted', () {
      // The parameters landed on the far side of the `#`, percent-escaped, so
      // nothing in the line looks like `password=` until it is decoded.
      // Decoding for readability must not be the one printed copy of the
      // credential.
      const line = 'failed to parse trojan://${Fixtures.uuid}'
          '@de1.vpn.example.com:443'
          '#Amsterdam%2003%3Fpassword%3D${Fixtures.password}'
          '%26sid%3D${Fixtures.shortId}';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.password)));
      expect(result, isNot(contains(Fixtures.shortId)));
      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, contains('Amsterdam 03'));
    });

    test('a uuid escaped into the node name stays redacted', () {
      const line = 'failed to parse vmess://${Fixtures.uuid}'
          '@de1.vpn.example.com:443#node%2D${Fixtures.uuid}';
      final result = redactor.redact(line);

      expect(result, isNot(contains(Fixtures.uuid)));
      expect(result, contains(Redact.placeholder));
    });

    test('a node name cannot forge a second record in the log', () {
      // A log record is one line. A name carrying `%0A` would arrive as two,
      // and the second one would read like something the core wrote.
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443'
          '#Amsterdam%0A2026-09-16%20INFO%20tunnel%20connected';
      final result = redactor.redact(line);

      expect(result, isNot(contains('\n')));
      expect(result, isNot(contains('\r')));
      expect(result, contains('Amsterdam 2026-09-16 INFO tunnel connected'));
    });

    test('a name with a broken escape is shown escaped, never dropped', () {
      // `%FF` is not valid UTF-8 and no decoder will take it. Half a name is
      // still a better error than no name.
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443#Ams%FFterdam';

      expect(redactor.redact(line), contains('#Ams%FFterdam'));
    });

    test('redacting twice changes nothing the first pass left', () {
      const line = 'failed to parse trojan://${Fixtures.uuid}'
          '@de1.vpn.example.com:443'
          '#Amsterdam%2003%3Fpassword%3D${Fixtures.password}';
      final once = redactor.redact(line);

      expect(redactor.redact(once), equals(once));
    });

    test('a value only shaped like the placeholder is still blanked', () {
      // The idempotence guard is a hole the moment it trusts a prefix: a value
      // that merely starts like `[redacted` is not one this redactor wrote.
      const line = 'trojan: dial with password=[redacted-not-really] sni=x';
      final result = redactor.redact(line);

      expect(result, isNot(contains('not-really')));
      expect(result, contains('sni=x'));
    });

    test('an already redacted json value is left as it stands', () {
      const line = '{"password":"${Redact.placeholder}","aid":0}';

      expect(redactor.redact(line), equals(line));
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

    test('hides the user own server hidden inside a node name', () {
      // The host is escaped on the far side of the `#`, so it only becomes a
      // host once the name is decoded — and an export must not be the place
      // where it reappears.
      final exporter = LogRedactor(
        serverHosts: () => <String>['de1.vpn.example.com'],
      );
      const line = 'failed to parse vless://${Fixtures.uuid}'
          '@de1.vpn.example.com:443#de1%2Evpn%2Eexample%2Ecom';

      expect(
        exporter.redactForExport(line),
        equals(
          'failed to parse vless://${Redact.placeholder}'
          '@${Redact.serverPlaceholder}:443#${Redact.serverPlaceholder}',
        ),
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
