import 'package:commy_core/commy_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemIntent.tryParse', () {
    test('reads a tapped protocol link', () {
      final intent = SystemIntent.tryParse(
        '{"kind":"link","uri":"vless://uuid@example.net:443"}',
      );

      expect(intent?.kind, SystemIntentKind.link);
      expect(intent?.payload, 'vless://uuid@example.net:443');
    });

    test('reads shared text', () {
      final intent = SystemIntent.tryParse(
        '{"kind":"text","text":"ss://example"}',
      );

      expect(intent?.kind, SystemIntentKind.text);
      expect(intent?.payload, 'ss://example');
    });

    test('reads an opened file', () {
      final intent = SystemIntent.tryParse(
        '{"kind":"file","uri":"content://downloads/1"}',
      );

      expect(intent?.kind, SystemIntentKind.file);
      expect(intent?.uri, 'content://downloads/1');
    });

    test('reads a Quick Settings tap, which carries nothing', () {
      final intent = SystemIntent.tryParse('{"kind":"connect"}');

      expect(intent?.kind, SystemIntentKind.connect);
      expect(intent?.payload, isNull);
    });

    test('a kind from a newer native side is skipped, not thrown', () {
      // This arrives on a stream nobody is placed to catch: throwing here
      // would tear the subscription down and silently kill every later link.
      expect(SystemIntent.tryParse('{"kind":"teleport"}'), isNull);
    });

    test('malformed JSON is skipped', () {
      expect(SystemIntent.tryParse('not json at all'), isNull);
      expect(SystemIntent.tryParse('[]'), isNull);
      expect(SystemIntent.tryParse('{"nokind":1}'), isNull);
    });

    test('an empty string field reads as absent', () {
      final intent = SystemIntent.tryParse('{"kind":"link","uri":""}');

      expect(intent?.payload, isNull);
    });

    test('toString never prints the link (rule R3)', () {
      // A vless:// URL carries the user's UUID, and this object is exactly the
      // kind of thing that ends up pasted into a bug report.
      final intent = SystemIntent.tryParse(
        '{"kind":"link","uri":"vless://11111111-2222-3333-4444-555555555555@h:1"}',
      );

      expect(intent.toString(), 'SystemIntent(link)');
      expect(intent.toString(), isNot(contains('11111111')));
    });
  });
}
