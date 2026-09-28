import 'dart:convert';
import 'dart:typed_data';

import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String hex) => Uint8List.fromList(<int>[
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Tiny parameters: the format and the checks are the same, the derivation
  // takes milliseconds instead of a second.
  PasswordBackupCipher tiny() =>
      PasswordBackupCipher(memoryKiB: 64, iterations: 1, parallelism: 1);

  final plain = Uint8List.fromList(
    utf8.encode('{"format":"commy-backup","schema":1,"uuid":"8f3c1e6a"}'),
  );
  const password = 'correct horse battery';

  group('the algorithms the format is built on', () {
    // Known answers from the RFCs, so a Dependabot bump of the library that
    // changed either primitive fails here and not on a user's restore.
    test('Argon2id matches RFC 9106, section 5.3', () async {
      const kdf = DartArgon2id(
        memory: 32,
        iterations: 3,
        parallelism: 4,
        hashLength: 32,
      );
      final key = await kdf.deriveKey(
        secretKey: SecretKey(List<int>.filled(32, 0x01)),
        nonce: List<int>.filled(16, 0x02),
        optionalSecret: List<int>.filled(8, 0x03),
        associatedData: List<int>.filled(12, 0x04),
      );

      expect(
        _toHex(await key.extractBytes()),
        '0d640df58d78766c08c037a34a8b53c9'
        'd01ef0452d75b65eb52520e96b01e659',
      );
    });

    test('ChaCha20-Poly1305 matches RFC 8439, section 2.8.2', () async {
      final box = await const DartChacha20.poly1305Aead().encrypt(
        utf8.encode(
          "Ladies and Gentlemen of the class of '99: If I could offer you "
          'only one tip for the future, sunscreen would be it.',
        ),
        secretKey: SecretKey(
          _hex(
            '808182838485868788898a8b8c8d8e8f'
            '909192939495969798999a9b9c9d9e9f',
          ),
        ),
        nonce: _hex('070000004041424344454647'),
        aad: _hex('50515253c0c1c2c3c4c5c6c7'),
      );

      expect(_toHex(box.mac.bytes), '1ae10b594f09e26a7e902ecbd0600691');
      expect(
        _toHex(box.cipherText.take(16).toList()),
        'd31a8d34648e60db7b86afbc53ef7ec2',
      );
    });
  });

  group('PasswordBackupCipher', () {
    test('what it seals, it opens with the same password', () async {
      final cipher = tiny();

      final sealed = (await cipher.seal(plain, password)).valueOrNull!;
      final opened = (await cipher.open(sealed, password)).valueOrNull;

      expect(opened, plain);
    });

    test('the file says "a Commy backup" and nothing else in the clear',
        () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;

      expect(ascii.decode(sealed.sublist(0, 8)), 'COMMYBAK');
      expect(PasswordBackupCipher.headerLength, 56);
      expect(
        sealed.length,
        PasswordBackupCipher.headerLength + plain.length + 16,
      );
      // Not a byte of the payload survives in the clear.
      expect(
        latin1.decode(sealed, allowInvalid: true),
        isNot(contains('uuid')),
      );
      expect(
        latin1.decode(sealed, allowInvalid: true),
        isNot(contains('commy-backup')),
      );
    });

    test('the header carries the parameters it was sealed with', () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final view = ByteData.sublistView(sealed);

      expect(sealed[8], 1, reason: 'container version');
      expect(sealed[9], 1, reason: 'Argon2id');
      expect(sealed[10], 1, reason: 'ChaCha20-Poly1305');
      expect(view.getUint32(12), 64);
      expect(view.getUint32(16), 1);
      expect(sealed[20], 1);
      expect(sealed[21], 16);
      expect(sealed[22], 12);
      expect(view.getUint32(52), plain.length);
    });

    test(
        'bytes after the tag are ignored: an overwritten longer file still '
        'opens', () async {
      // The save dialog can hand back an existing file, and a provider that
      // does not truncate on "w" leaves the old file's tail behind.
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;
      final withTail =
          Uint8List.fromList(<int>[...sealed, ...List.filled(500, 7)]);

      expect((await cipher.open(withTail, password)).valueOrNull, plain);
    });

    test('a shortened length fails authentication', () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final shorter = Uint8List.fromList(sealed);
      ByteData.sublistView(shorter).setUint32(52, plain.length - 1);

      expect(
        (await tiny().open(shorter, password)).failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('a length pointing past the end of the file is damage', () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final lying = Uint8List.fromList(sealed);
      ByteData.sublistView(lying).setUint32(52, sealed.length);

      expect(tiny().inspect(lying), BackupProblem.unreadable);
    });

    test('two seals of the same data share neither salt nor nonce', () async {
      final cipher = tiny();
      final a = (await cipher.seal(plain, password)).valueOrNull!;
      final b = (await cipher.seal(plain, password)).valueOrNull!;

      expect(a.sublist(24, 40), isNot(b.sublist(24, 40)));
      expect(a.sublist(40, 52), isNot(b.sublist(40, 52)));
      expect(a.sublist(52), isNot(b.sublist(52)));
    });

    test('a wrong password is a wrong password', () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;

      final result = await cipher.open(sealed, 'correct horse battery!');

      expect(
        result.failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('the whole header is authenticated, not only the ciphertext',
        () async {
      // Derive the key the way the cipher does and open the box by hand:
      // with the header as associated data it opens, without it it must
      // not — which is only true if sealing bound the header in.
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final header = sealed.sublist(0, PasswordBackupCipher.headerLength);
      final key = await const DartArgon2id(
        memory: 64,
        iterations: 1,
        parallelism: 1,
        hashLength: 32,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: header.sublist(24, 40),
      );
      final box = SecretBox(
        sealed.sublist(PasswordBackupCipher.headerLength, sealed.length - 16),
        nonce: header.sublist(40, 52),
        mac: Mac(sealed.sublist(sealed.length - 16)),
      );
      const aead = DartChacha20.poly1305Aead();

      expect(await aead.decrypt(box, secretKey: key, aad: header), plain);
      await expectLater(
        aead.decrypt(box, secretKey: key),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('the password is taken as typed: every variation is another one',
        () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;

      // Case, a trailing space, a composed "й" typed as "и" + breve: each
      // is a different password, because each is different bytes.
      for (final other in <String>[
        password.toUpperCase(),
        '$password ',
        password.trimRight().substring(0, password.length - 1),
      ]) {
        expect(
          (await cipher.open(sealed, other)).failureOrNull,
          const BackupFailure(BackupProblem.wrongPassword),
          reason: other,
        );
      }
      final composed = (await cipher.seal(plain, 'пароль-й')).valueOrNull!;
      expect(
        (await cipher.open(composed, 'пароль-и\u0306')).failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('every header bound is checked before any work', () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      Uint8List edited(void Function(ByteData view) edit) {
        final copy = Uint8List.fromList(sealed);
        edit(ByteData.sublistView(copy));
        return copy;
      }

      final refused = <String, Uint8List>{
        'no lanes': edited((v) => v.setUint8(20, 0)),
        'too many lanes': edited((v) => v.setUint8(20, 9)),
        'less memory than lanes need': edited((v) {
          v
            ..setUint8(20, 8)
            ..setUint32(12, 63);
        }),
        'no passes': edited((v) => v.setUint32(16, 0)),
        'too much memory': edited((v) => v.setUint32(12, 131073)),
        'a salt of another length': edited((v) => v.setUint8(21, 32)),
        'a nonce of another length': edited((v) => v.setUint8(22, 24)),
        'the reserved byte set': edited((v) => v.setUint8(23, 1)),
      };
      for (final entry in refused.entries) {
        expect(
          tiny().inspect(entry.value),
          BackupProblem.unreadable,
          reason: entry.key,
        );
      }
      // And the largest allowed values are allowed.
      expect(
        tiny().inspect(
          edited((v) {
            v
              ..setUint32(12, 131072)
              ..setUint32(16, 6)
              ..setUint8(20, 8);
          }),
        ),
        isNull,
      );
    });

    test('the password is taken as typed: no trimming', () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;

      final result = await cipher.open(sealed, ' $password');

      expect(
        result.failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('a changed byte anywhere after the magic fails authentication',
        () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;
      // A salt byte, a nonce byte, a ciphertext byte and a tag byte.
      for (final at in <int>[30, 45, 60, sealed.length - 1]) {
        final changed = Uint8List.fromList(sealed)..[at] ^= 0x01;

        final result = await cipher.open(changed, password);

        expect(
          result.failureOrNull,
          const BackupFailure(BackupProblem.wrongPassword),
          reason: 'byte $at',
        );
      }
    });

    test('changed Argon2 parameters within bounds derive another key',
        () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;
      final changed = Uint8List.fromList(sealed);
      ByteData.sublistView(changed).setUint32(16, 2);

      final result = await cipher.open(changed, password);

      expect(
        result.failureOrNull,
        const BackupFailure(BackupProblem.wrongPassword),
      );
    });

    test('a file that is not a backup is turned away before the password', () {
      final cipher = tiny();

      expect(
        cipher.inspect(Uint8List.fromList(utf8.encode('vless://abc'))),
        BackupProblem.notABackup,
      );
      expect(cipher.inspect(Uint8List(0)), BackupProblem.notABackup);
      expect(
        cipher.inspect(Uint8List.fromList(utf8.encode('{"a":1}'))),
        BackupProblem.notABackup,
      );
    });

    test('a newer container version or algorithm asks for a newer Commy',
        () async {
      final cipher = tiny();
      final sealed = (await cipher.seal(plain, password)).valueOrNull!;

      for (final at in <int>[8, 9, 10, 11]) {
        final changed = Uint8List.fromList(sealed)..[at] = 2;
        expect(
          cipher.inspect(changed),
          BackupProblem.newerVersion,
          reason: 'byte $at',
        );
        expect(
          (await cipher.open(changed, password)).failureOrNull,
          const BackupFailure(BackupProblem.newerVersion),
        );
      }
    });

    test('a truncated backup is damaged, not "not a backup"', () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;

      expect(tiny().inspect(sealed.sublist(0, 60)), BackupProblem.unreadable);
    });

    test('parameters past twice what this version writes are refused',
        () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final costly = Uint8List.fromList(sealed);
      ByteData.sublistView(costly).setUint32(16, 7);

      expect(tiny().inspect(costly), BackupProblem.unreadable);
    });

    test('a header asking for absurd memory is refused before any work',
        () async {
      final sealed = (await tiny().seal(plain, password)).valueOrNull!;
      final greedy = Uint8List.fromList(sealed);
      // 4 GiB of Argon2 memory: a crafted file must not get to allocate it.
      ByteData.sublistView(greedy).setUint32(12, 0x400000);

      expect(tiny().inspect(greedy), BackupProblem.unreadable);
      expect(
        (await tiny().open(greedy, password)).failureOrNull,
        const BackupFailure(BackupProblem.unreadable),
      );
    });

    test('the recommended parameters seal and open, on a worker isolate',
        () async {
      // The one test at production strength: about a second in the VM.
      final cipher = PasswordBackupCipher();

      final sealed = (await cipher.seal(plain, password)).valueOrNull!;
      final view = ByteData.sublistView(sealed);

      expect(view.getUint32(12), 65536);
      expect(view.getUint32(16), 3);
      expect(sealed[20], 4);
      expect((await cipher.open(sealed, password)).valueOrNull, plain);
    });

    test('a file sealed by this format version still opens', () async {
      // Sealed once with tiny parameters and committed. If a library bump or
      // a refactor changes how bytes are sealed, users' existing backups stop
      // opening — this is where that shows up first.
      final fixture = _hex(_fixtureHex);

      final opened = await tiny().open(fixture, 'fixture password');

      expect(utf8.decode(opened.valueOrNull!), 'Commy backup fixture, v1');
    });
  });
}

// PasswordBackupCipher(memoryKiB: 64, iterations: 1, parallelism: 1)
//   .seal(utf8.encode('Commy backup fixture, v1'), 'fixture password')
const String _fixtureHex =
    '434f4d4d5942414b01010100000000400000000101100c003f9ea1c6546f0912'
    '32fe288c60e05e6d47edfe703966de3c858e1e440000001878b14885238e3a87'
    '38f632aec2ad77a3072005e2c95aa86a09558c8e46295d7ec6f5000e52a176d7';
