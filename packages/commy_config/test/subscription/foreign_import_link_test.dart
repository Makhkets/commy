import 'dart:convert';

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

    // Commy's own "add" link, shaped like everyone else's (`happ://add/`):
    // the address as it is, percent-encoded, or as `?url=`, with a name.
    test('commy://add/ is our own add link', () {
      for (final link in <String>[
        'commy://add/$sub',
        'commy://add/$encoded',
        'commy://add?url=$encoded',
        'COMMY://add/$sub',
      ]) {
        expect(unwrap(link)?.url, Uri.parse(sub), reason: link);
      }
      expect(unwrap('commy://add/$sub#Home')?.name, 'Home');
      expect(unwrap('commy://add?url=$encoded&name=Work')?.name, 'Work');
    });

    // The buttons of Remnawave's stock subscription page, copied from its
    // default app-config.json, and the forms the owner's panel bots send.
    test('the path forms of INCY, v2RayTun, Streisand and Hiddify', () {
      for (final link in <String>[
        'incy://import/$sub',
        'incy://import/$encoded',
        'incy://add/$sub',
        'v2raytun://import/$sub',
        'v2raytun://import/$encoded',
        'streisand://import/$sub',
        'hiddify://import/$sub',
      ]) {
        expect(unwrap(link)?.url, Uri.parse(sub), reason: link);
      }
      expect(unwrap('hiddify://import/$sub#Office')?.name, 'Office');
    });

    test('the install-config buttons of the Clash family and v2rayNG', () {
      for (final link in <String>[
        'clash://install-config?overwrite=no&name=Remnawave&url=$encoded',
        'clashmeta://install-config?name=Remnawave&url=$encoded',
        'flclashx://install-config?url=$encoded',
        'stash://install-config?url=$encoded',
        'koala-clash://install-config?url=$encoded',
        'prizrak-box://install-config?url=$encoded',
        'v2rayng://install-config?name=Remnawave&url=$encoded',
        'exclave://subscription?url=$encoded',
      ]) {
        expect(unwrap(link)?.url, Uri.parse(sub), reason: link);
      }
      expect(
        unwrap('v2rayng://install-config?name=Remnawave&url=$encoded')?.name,
        'Remnawave',
        reason: 'The name is handed on as written; the use case ranks it.',
      );
    });

    test("Shadowrocket's sub://, base64 and query spellings, bare or wrapped",
        () {
      final b64 = base64.encode(utf8.encode(sub));
      final urlSafe = base64Url.encode(utf8.encode(sub)).replaceAll('=', '');
      for (final link in <String>[
        'sub://$b64',
        'sub://$urlSafe',
        'sub://${Uri.encodeComponent(b64)}',
        'sub://$b64#Home',
        'sub://?url=$encoded&remark=Home',
        'shadowrocket://add/sub://$b64?remark=Home',
        'shadowrocket://add/sub://?url=$encoded&remark=Home',
      ]) {
        expect(unwrap(link)?.url, Uri.parse(sub), reason: link);
      }
      expect(unwrap('sub://$b64#Home')?.name, 'Home');
      expect(unwrap('sub://?url=$encoded&remark=Home')?.name, 'Home');
      expect(
        unwrap('shadowrocket://add/sub://$b64?remark=My%20VPN')?.name,
        'My VPN',
      );
      expect(unwrap('sub://$b64')?.name, isNull);
    });

    test('a base64 that is not an http address is not a subscription', () {
      final notWeb = base64.encode(utf8.encode('vless://uuid@a.example:443'));
      expect(unwrap('sub://$notWeb'), isNull);
      expect(unwrap('sub://!!!'), isNull);
      expect(unwrap('sub://'), isNull);
      expect(unwrap('shadowrocket://add/'), isNull);
    });

    test('a single server inside a path form comes out for the parser', () {
      const vless = 'vless://uuid@a.example:443?security=reality#Node';
      expect(
        ForeignImportLink.innerLink(
          'v2raytun://import/${Uri.encodeComponent(vless)}',
        ),
        vless,
      );
      expect(ForeignImportLink.innerLink('incy://import/$vless'), vless);
      expect(ForeignImportLink.innerLink('v2raytun://import/$sub'), isNull);
      expect(ForeignImportLink.innerLink('happ://crypt5/AAAA'), isNull);
      expect(ForeignImportLink.innerLink(vless), isNull);
      expect(ForeignImportLink.innerLink('v2raytun://import/plain'), isNull);
    });

    test('encrypted links name their client, and only those', () {
      expect(ForeignImportLink.encryptedBy('happ://crypt5/AbC'), 'Happ');
      expect(ForeignImportLink.encryptedBy('happ://crypt/AbC'), 'Happ');
      expect(ForeignImportLink.encryptedBy('INCY://CRYPT1/AbC'), 'INCY');
      expect(ForeignImportLink.encryptedBy('happ://add/$sub'), isNull);
      expect(ForeignImportLink.encryptedBy('happ://cryptic'), isNull);
      expect(ForeignImportLink.encryptedBy('v2raytun://crypt1/x'), isNull);
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
