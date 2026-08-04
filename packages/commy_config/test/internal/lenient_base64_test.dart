import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

void main() {
  group('LenientBase64', () {
    test('decodes standard base64 with padding', () {
      expect(LenientBase64.decodeToString('aGVsbG8gd29ybGQ='), 'hello world');
    });

    test('decodes url-safe base64 without padding', () {
      const source = 'vless://uuid@a.example:443?x=1%2F2#Name';
      final encoded = LenientBase64.encodeUrlSafe(source);

      expect(encoded, isNot(contains('=')));
      expect(LenientBase64.decodeToString(encoded), source);
    });

    test('ignores whitespace and line breaks a panel inserts', () {
      final wrapped = LenientBase64.encode('hello world there')
          .replaceAllMapped(RegExp('.{4}'), (match) => '${match[0]}\n');

      expect(LenientBase64.decodeToString(wrapped), 'hello world there');
    });

    test('refuses a string that is not the base64 alphabet', () {
      expect(LenientBase64.decodeToString('vless://uuid@a.example'), isNull);
    });

    test('refuses a string too short to mean anything', () {
      expect(LenientBase64.decodeToString('abc'), isNull);
    });

    test('refuses a length that cannot be base64', () {
      expect(LenientBase64.decodeToString('abcdefghi'), isNull);
    });

    test('refuses bytes that are not text', () {
      // Sixteen zero bytes: valid base64, useless as a subscription body.
      expect(LenientBase64.decodeToString('AAAAAAAAAAAAAAAAAAAAAA=='), isNull);
    });

    test('round trips utf-8 outside ascii', () {
      const source = 'Мой профиль';

      expect(
        LenientBase64.decodeToString(LenientBase64.encode(source)),
        source,
      );
    });

    test('isMostlyPrintable allows tabs and newlines', () {
      final tabbed = String.fromCharCodes(<int>[0x61, 0x09, 0x62, 0x0A]);
      final control = String.fromCharCodes(<int>[0x00, 0x01, 0x02]);

      expect(LenientBase64.isMostlyPrintable(tabbed), isTrue);
      expect(LenientBase64.isMostlyPrintable(control), isFalse);
      expect(LenientBase64.isMostlyPrintable(''), isFalse);
    });
  });
}
