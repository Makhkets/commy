import 'package:commy_config/commy_config.dart';
import 'package:test/test.dart';

void main() {
  const sub = 'https://sub.example.net/api/sub/AbC123?format=raw';
  final encoded = Uri.encodeComponent(sub);

  ({Uri url, String? name})? unwrap(String input) =>
      ForeignImportLink.unwrap(input);

  group('ForeignImportLink', () {
    test("Happ's add link, as Remnawave and Marzban pages write it", () {
      expect(unwrap('happ://add/$sub')?.url, Uri.parse(sub));
      expect(unwrap('HAPP://ADD/$sub')?.url, Uri.parse(sub));
      expect(unwrap('happ://add/$encoded')?.url, Uri.parse(sub));
      expect(unwrap('happ://add/$sub')?.name, isNull);
    });

    test('a name on the address is taken as the name, and taken off', () {
      final result = unwrap('happ://add/$sub#My%20panel');

      expect(result?.url, Uri.parse(sub));
      expect(result?.name, 'My panel');
    });

    test("sing-box's remote profile, the name in the fragment", () {
      final result = unwrap(
        'sing-box://import-remote-profile?url=$encoded#Home',
      );

      expect(result?.url, Uri.parse(sub));
      expect(result?.name, 'Home');
    });

    test("Clash's install-config and NekoBox's subscription, name= too", () {
      for (final link in <String>[
        'clash://install-config?url=$encoded&name=Work',
        'sn://subscription?url=$encoded&name=Work',
        'commy://install-config?url=$encoded&name=Work',
      ]) {
        final result = unwrap(link);
        expect(result?.url, Uri.parse(sub), reason: link);
        expect(result?.name, 'Work', reason: link);
      }
    });

    test('a name with a broken escape is kept as written', () {
      expect(unwrap('happ://add/$sub#100%')?.name, '100%');
    });

    test('our own scheme, in the path form too', () {
      expect(unwrap('commy://import/$sub')?.url, Uri.parse(sub));
    });

    test('nothing that is not an http address comes out', () {
      for (final link in <String>[
        'happ://add/vless://uuid@a.example:443',
        'happ://crypt3/AAAA',
        'happ://add/',
        'sing-box://import-remote-profile?url=file%3A%2F%2F%2Fetc%2Fhosts',
        'sing-box://import-remote-profile',
        'clash://install-config?url=https%3A%2F%2F',
        'clash://proxies?url=$encoded',
        'vless://uuid@a.example:443',
        sub,
        'happ://add/$sub trailing words',
        'happ://add/https%3A%2F%2Fbroken%ZZ',
        '',
      ]) {
        expect(unwrap(link), isNull, reason: link);
      }
    });
  });
}
