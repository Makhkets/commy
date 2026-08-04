import 'package:commy_core/commy_core.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// The strings here are shaped like the real thing on purpose. A redactor
/// tested on `password=secret` passes while leaking every credential this app
/// actually handles, because none of them look like that.
void main() {
  const uuid = '7f3c1a2b-4d5e-6f70-8192-a3b4c5d6e7f8';
  const token = '9f8e7d6c5b4a32100fedcba987654321';

  group('DefaultLogRedaction', () {
    test('removes a bare UUID, the whole credential of VLESS and VMess', () {
      final result = DefaultLogRedaction.apply(
        'outbound/vless[proxy]: dial failed for user $uuid',
      );

      expect(result, isNot(contains(uuid)));
      expect(result, contains(Redact.placeholder));
      expect(result, contains('outbound/vless[proxy]: dial failed'));
    });

    test('removes the credentials of a vless:// link, keeping the name', () {
      const link = 'vless://$uuid@203.0.113.9:443'
          '?type=tcp&security=reality&pbk=Zm9vYmFy&sid=ab12#NL-03';

      final result = DefaultLogRedaction.apply('failed to parse $link');

      expect(result, isNot(contains(uuid)));
      expect(result, isNot(contains('Zm9vYmFy')));
      expect(result, isNot(contains('ab12')));
      // The fragment survives: it is the node's display name, and without it
      // the error names no node at all.
      expect(result, contains('NL-03'));
      expect(result, contains('203.0.113.9'));
    });

    test('removes a subscription token hiding in the path', () {
      const url = 'https://panel.example.com/api/v1/client/subscribe/$token';

      final result = DefaultLogRedaction.apply('GET $url returned 200');

      expect(result, isNot(contains(token)));
      expect(result, contains('panel.example.com'));
      expect(result, contains('returned 200'));
    });

    test('removes a subscription token hiding in the query', () {
      const url = 'https://panel.example.com/sub?token=$token';

      final result = DefaultLogRedaction.apply('fetching $url');

      expect(result, isNot(contains(token)));
      expect(result, contains('panel.example.com'));
    });

    test('removes credential-shaped fields, including JSON fragments', () {
      final result = DefaultLogRedaction.apply(
        'config: {"uuid": "$uuid", "password": "hunter2", '
        '"private_key": "cGsx", "short_id": "ab12"}',
      );

      expect(result, isNot(contains('hunter2')));
      expect(result, isNot(contains('cGsx')));
      expect(result, isNot(contains('ab12')));
      expect(result, isNot(contains(uuid)));
    });

    test('removes an Authorization header', () {
      final result = DefaultLogRedaction.apply(
        'Authorization: Bearer $token',
      );

      expect(result, isNot(contains(token)));
    });

    test('keeps the sentence around a URL readable', () {
      final result = DefaultLogRedaction.apply(
        'probe http://cp.cloudflare.com/generate_204, retrying.',
      );

      expect(result, startsWith('probe http://cp.cloudflare.com'));
      expect(result, endsWith('retrying.'));
    });

    test('leaves a line with no secrets untouched', () {
      const line = 'router: match[7] geosite=ads => reject';

      expect(DefaultLogRedaction.apply(line), line);
    });

    test('handles an empty message', () {
      expect(DefaultLogRedaction.apply(''), '');
    });

    test('is idempotent, so a re-redacted export is still readable', () {
      final once = DefaultLogRedaction.apply('fetch https://x.example/$token');
      final twice = DefaultLogRedaction.apply(once);

      expect(twice, once);
    });
  });
}
