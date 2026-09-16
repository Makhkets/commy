import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

/// `Redact` is the one place that decides what a user is allowed to see of a
/// link they pasted, so both halves of that decision are pinned here: what has
/// to disappear (rule R3) and what has to survive readable, because a report
/// naming no node is a report nobody can act on.
void main() {
  const uuid = '11111111-2222-3333-4444-555555555555';
  const publicKey = 'aGVsbG8td29ybGQtcHVibGljLWtleQ';

  group('Redact.link', () {
    test('shows the node name the way the user typed it, not escaped', () {
      const link = 'vless://$uuid@nl-03.example.net:443'
          '?security=reality&pbk=$publicKey&sid=ab12cd34#Amsterdam%2003';

      expect(
        Redact.link(link),
        'vless://${Redact.placeholder}@nl-03.example.net:443'
        '?${Redact.placeholder}#Amsterdam 03',
      );
    });

    test('keeps a name that is a flag, a dash and a non-Latin word', () {
      const link = 'vless://$uuid@de-01.example.net:443'
          '#%F0%9F%87%A9%F0%9F%87%AA%20Frankfurt%20%E2%80%94%20%D0%BE%D1%81%D0'
          '%BD%D0%BE%D0%B2%D0%BD%D0%BE%D0%B9';

      expect(
        Redact.link(link),
        'vless://${Redact.placeholder}@de-01.example.net:443'
        '#🇩🇪 Frankfurt — основной',
      );
    });

    test('blanks the credential, the query and the path of a link', () {
      const link = 'vless://$uuid@nl-03.example.net:443/ws-path'
          '?security=reality&pbk=$publicKey&sid=ab12cd34#Amsterdam%2003';

      final result = Redact.link(link);

      expect(result, isNot(contains(uuid)));
      expect(result, isNot(contains(publicKey)));
      expect(result, isNot(contains('ab12cd34')));
      expect(result, isNot(contains('ws-path')));
      expect(result, contains('nl-03.example.net:443'));
    });

    test('a credential hidden in the node name is not a way out of R3', () {
      // The parameters landed on the far side of the `#`, so `Uri` reads them
      // as the name rather than as the query. Decoding for readability must
      // not turn that into the one printed copy of the credential.
      const link = 'trojan://$uuid@nl-03.example.net:443'
          '#Amsterdam%2003%3Fpassword%3Dhunter2%26sid%3Dab12cd34';

      final result = Redact.link(link);

      expect(result, isNot(contains('hunter2')));
      expect(result, isNot(contains('ab12cd34')));
      expect(result, isNot(contains(uuid)));
      expect(result, contains('Amsterdam 03'));
    });

    test('a bare UUID written into the node name is blanked too', () {
      const link = 'vmess://$uuid@nl-03.example.net:443#$uuid';

      final result = Redact.link(link);

      expect(result, isNot(contains(uuid)));
      expect(result, contains(Redact.placeholder));
    });

    test('a name cannot forge a second line in an exported log', () {
      const link = 'vless://$uuid@nl-03.example.net:443'
          '#Amsterdam%0A2026-09-16%20INFO%20tunnel%20connected';

      final result = Redact.link(link);

      expect(result, isNot(contains('\n')));
      expect(result, contains('Amsterdam 2026-09-16 INFO tunnel connected'));
    });

    test('a name with a broken escape is shown escaped, never dropped', () {
      // `%FF` is not valid UTF-8 and the decoder refuses it. Half a name beats
      // no name, and it must not take the whole redaction down with it.
      const link = 'vless://$uuid@nl-03.example.net:443#Ams%FFterdam';

      expect(
        Redact.link(link),
        'vless://${Redact.placeholder}@nl-03.example.net:443#Ams%FFterdam',
      );
    });

    test('a link without a fragment gains neither name nor hash', () {
      const link = 'ss://Y2hhY2hhMjA=@se-02.example.net:8388';

      expect(
        Redact.link(link),
        'ss://${Redact.placeholder}@se-02.example.net:8388',
      );
    });

    test('anything that is not a link at all becomes the placeholder', () {
      expect(
        Redact.link('a shopping list, copied by accident'),
        Redact.placeholder,
      );
      expect(Redact.link(''), Redact.placeholder);
      expect(Redact.link('vless://'), Redact.placeholder);
    });
  });

  group('ImportFailure.redactedLine', () {
    test('names the node that failed without naming its credential', () {
      const failure = ImportFailure(
        rawLine: 'vless://$uuid@nl-03.example.net:443'
            '?security=reality&pbk=$publicKey#Amsterdam%2003',
        reason: 'unsupported flow',
      );

      expect(
        failure.redactedLine,
        'vless://${Redact.placeholder}@nl-03.example.net:443'
        '?${Redact.placeholder}#Amsterdam 03',
      );
      expect(failure.toString(), isNot(contains(uuid)));
    });
  });
}
