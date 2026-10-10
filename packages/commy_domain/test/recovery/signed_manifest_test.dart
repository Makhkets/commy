import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';
import 'package:test/test.dart';

import '../support/recovery_fakes.dart';

/// The wire format of docs/adr/0019-subscription-domain-recovery.md.
///
/// The string arrives from the network, and everything it names becomes an
/// address the client may talk to: every limit is a refusal, never a repair.
void main() {
  group('SignedManifest.parse', () {
    test('reads a well-formed manifest and what was signed', () {
      final compact = compactOf(manifestJson(nextKey: testKey(9)));

      final signed = SignedManifest.parse(compact)!;

      final manifest = signed.manifest;
      expect(manifest.id, 'axm');
      expect(manifest.seq, 1);
      expect(manifest.origin, Uri.parse('https://sub.example.com'));
      expect(manifest.mirrors, <Uri>[Uri.parse('https://mirror.example.org')]);
      expect(
        manifest.rendezvous,
        <Uri>[Uri.parse('https://meet.example.net/r/axm')],
      );
      expect(manifest.name, 'AXM VPN');
      expect(manifest.nextKey, testKey(9));
      expect(manifest.issuedAt.isUtc, isTrue);
      expect(signed.publicKey, List<int>.filled(32, 7));
      expect(signed.signature, hasLength(64));
      // Exactly the version and the payload, as ASCII: the signature covers
      // the version too, so a v2 reader cannot be fed a v1 signature.
      expect(
        ascii.decode(signed.signedBytes),
        compact.substring(0, compact.lastIndexOf('.')),
      );
    });

    test('an origin keeps its port and loses nothing else', () {
      final signed = SignedManifest.parse(
        compactOf(manifestJson(origin: 'https://Sub.Example.com:8443')),
      );

      expect(
        signed?.manifest.origin,
        Uri.parse('https://sub.example.com:8443'),
      );
    });

    test('duplicates in a list are folded, the order kept', () {
      final signed = SignedManifest.parse(
        compactOf(
          manifestJson(
            mirrors: <String>[
              'https://b.example',
              'https://a.example',
              'https://b.example',
            ],
          ),
        ),
      );

      expect(
        signed?.manifest.mirrors,
        <Uri>[Uri.parse('https://b.example'), Uri.parse('https://a.example')],
      );
    });

    test('a manifest round-trips through its stored form', () {
      final manifest =
          SignedManifest.parse(compactOf(manifestJson()))!.manifest;

      expect(RecoveryManifest.fromJson(manifest.toJson()), manifest);
    });

    group('refuses', () {
      final cases = <String, String>{
        'an empty string': '',
        'two parts': 'v1.abc',
        'another version': compactOf(manifestJson()).replaceFirst('v1.', 'v2.'),
        'a payload that is not base64url': 'v1.\$\$\$.${'A' * 86}',
        'a short signature':
            '${compactOf(manifestJson()).split('.').take(2).join('.')}.AAAA',
        'a payload that is not JSON': 'v1.${_b64(utf8.encode('nope'))}'
            '.${_b64(List<int>.filled(64, 1))}',
        'a version field of 2': compactOf(
          <String, Object?>{...manifestJson(), 'v': 2},
        ),
        'an id with a slash': compactOf(manifestJson(id: 'a/b')),
        'an id too long': compactOf(manifestJson(id: 'x' * 65)),
        'a zero seq': compactOf(manifestJson(seq: 0)),
        'a seq that is a string':
            compactOf(<String, Object?>{...manifestJson(), 'seq': '3'}),
        'an origin with a path':
            compactOf(manifestJson(origin: 'https://sub.example.com/sub')),
        'an origin with a query':
            compactOf(manifestJson(origin: 'https://sub.example.com?x=1')),
        'an origin with credentials':
            compactOf(manifestJson(origin: 'https://u:p@sub.example.com')),
        'an origin that is not the web':
            compactOf(manifestJson(origin: 'ftp://sub.example.com')),
        'a mirror with a path': compactOf(
          manifestJson(mirrors: <String>['https://m.example/sub']),
        ),
        'too many mirrors': compactOf(
          manifestJson(
            mirrors: <String>[
              for (var i = 0; i < 9; i++) 'https://m$i.example',
            ],
          ),
        ),
        'a meeting point over plain http': compactOf(
          manifestJson(rendezvous: <String>['http://meet.example.net/r/a']),
        ),
        'too many meeting points': compactOf(
          manifestJson(
            rendezvous: <String>[
              for (var i = 0; i < 5; i++) 'https://r$i.example/x',
            ],
          ),
        ),
        'a key of the wrong length':
            compactOf(manifestJson(key: base64Url.encode(<int>[1, 2, 3]))),
        'a next key of the wrong length':
            compactOf(manifestJson(nextKey: 'AAAA')),
        'a blank name': compactOf(manifestJson(name: '   ')),
        'a name too long': compactOf(manifestJson(name: 'n' * 65)),
        'anything longer than 4096': 'v1.${'A' * 5000}.${'A' * 86}',
      };
      for (final entry in cases.entries) {
        test(entry.key, () {
          expect(SignedManifest.parse(entry.value), isNull);
        });
      }
    });
  });

  group('SignedManifest.originOf', () {
    test('keeps scheme, host and an explicit port only', () {
      expect(
        SignedManifest.originOf(
          Uri.parse('https://user@Sub.Example.com:8443/sub/t?x=1#f'),
        ),
        Uri.parse('https://sub.example.com:8443'),
      );
      expect(
        SignedManifest.originOf(Uri.parse('http://a.example/sub')),
        Uri.parse('http://a.example'),
      );
      expect(SignedManifest.originOf(Uri.parse('vless://a@b:1')), isNull);
    });
  });
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
