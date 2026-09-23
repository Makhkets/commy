import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ru = Locale('ru');
  const en = Locale('en');

  group('CommyByteFormat', () {
    test('English keeps Latin symbols and a decimal point', () {
      expect(CommyByteFormat.bytes(512, locale: en), '512 B');
      expect(CommyByteFormat.bytes(1536, locale: en), '1.5 KB');
      expect(CommyByteFormat.bytes(6 << 30, locale: en), '6.0 GB');
      expect(CommyByteFormat.rate(38000, locale: en), '37 KB/s');
      expect(CommyByteFormat.rate(3800, locale: en), '3.7 KB/s');
    });

    // Seen on the emulator in the owner's language: "6.0 GB из 100 GB",
    // "0 B/s". Russian spells the unit in Cyrillic and writes a comma.
    test('Russian writes Cyrillic symbols and a decimal comma', () {
      expect(CommyByteFormat.bytes(512, locale: ru), '512 Б');
      expect(CommyByteFormat.bytes(1536, locale: ru), '1,5 КБ');
      expect(CommyByteFormat.bytes(6 << 30, locale: ru), '6,0 ГБ');
      expect(CommyByteFormat.bytes(100 << 30, locale: ru), '100 ГБ');
      expect(CommyByteFormat.rate(0, locale: ru), '0 Б/с');
      expect(CommyByteFormat.rate(38000, locale: ru), '37 КБ/с');
      expect(CommyByteFormat.rate(3800, locale: ru), '3,7 КБ/с');
    });

    test('no locale is the Latin form', () {
      expect(CommyByteFormat.bytes(1536), '1.5 KB');
      expect(CommyByteFormat.rate(1536), '1.5 KB/s');
    });

    test('a negative count keeps its sign in either language', () {
      expect(CommyByteFormat.bytes(-1536, locale: ru), '-1,5 КБ');
      expect(CommyByteFormat.bytes(-1536, locale: en), '-1.5 KB');
    });
  });
}
