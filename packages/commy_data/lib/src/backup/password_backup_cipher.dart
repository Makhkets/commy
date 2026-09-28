import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:commy_domain/commy_domain.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Seals a backup with Argon2id and ChaCha20-Poly1305 under the user's
/// password. The format and every number in it:
/// docs/adr/0017-encrypted-backup.md.
///
/// ```text
/// offset  size  field
///      0     8  magic "COMMYBAK"
///      8     1  container version (1)
///      9     1  KDF: 1 = Argon2id v1.3
///     10     1  AEAD: 1 = ChaCha20-Poly1305 (RFC 8439)
///     11     1  flags (0)
///     12     4  Argon2 memory, KiB   (big-endian)
///     16     4  Argon2 iterations    (big-endian)
///     20     1  Argon2 parallelism
///     21     1  salt length (16)
///     22     1  nonce length (12)
///     23     1  reserved (0)
///     24    16  salt
///     40    12  nonce
///     52     4  ciphertext length n  (big-endian)
///     56     n  ciphertext
///   56+n    16  Poly1305 tag
///   56+n+16  …  ignored
/// ```
///
/// The whole 56-byte header is the AEAD's associated data, so a flipped bit in
/// the parameters fails authentication like a flipped bit in the ciphertext.
/// Nothing inside the file identifies the user outside the ciphertext — no
/// date, no version, no count: an intercepted file says "a Commy backup" and
/// nothing more. (The name the save dialog proposes carries the day; the user
/// can change it.)
///
/// The length is there because of how the file is written. Android's save
/// dialog can hand back an existing file to overwrite, and `file_picker`
/// opens it with `openOutputStream(uri)` — mode "w", which some document
/// providers do not truncate. A shorter backup written over a longer one
/// would keep the old tail, and a tag read from the end of the file would be
/// the old file's: a backup that never opens. With the length, the tail is
/// just ignored.
///
/// The Argon2 parameters travel in the header, so they can be raised later
/// without a new container version; a reader bounds them before deriving
/// anything, so a crafted file cannot ask for a gigabyte of memory.
///
/// Key derivation and encryption run in a separate isolate: at the recommended
/// parameters the derivation takes about a second on a phone, and on the UI
/// isolate that second would be a frozen screen.
class PasswordBackupCipher implements BackupCipher {
  /// Creates the cipher. The defaults are RFC 9106's second recommended
  /// option; tests pass tiny ones.
  PasswordBackupCipher({
    this.memoryKiB = recommendedMemoryKiB,
    this.iterations = recommendedIterations,
    this.parallelism = recommendedParallelism,
    Random? random,
    this.inIsolate = true,
  }) : _random = random ?? Random.secure();

  /// Argon2id memory: 64 MiB.
  static const int recommendedMemoryKiB = 65536;

  /// Argon2id passes.
  static const int recommendedIterations = 3;

  /// Argon2id lanes.
  static const int recommendedParallelism = 4;

  /// "COMMYBAK".
  static const List<int> magic = <int>[
    0x43, 0x4F, 0x4D, 0x4D, 0x59, 0x42, 0x41, 0x4B, //
  ];

  /// The container layout this version writes and reads.
  static const int containerVersion = 1;

  /// Bytes before the ciphertext; all of them are authenticated.
  static const int headerLength = 56;

  static const int _kdfArgon2id = 1;
  static const int _aeadChacha20Poly1305 = 1;
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _tagLength = 16;
  static const int _keyLength = 32;

  /// Larger than any backup a phone could make; a bigger file is not ours.
  static const int maxFileBytes = 32 * 1024 * 1024;

  // What a reader accepts from a header before it spends anything on it:
  // twice the memory and twice the passes this version writes, so a later
  // Commy can raise its parameters without a new container version, and a
  // crafted file cannot make an open cost much more than a real one does.
  static const int _maxMemoryKiB = 2 * recommendedMemoryKiB;
  static const int _maxIterations = 2 * recommendedIterations;
  static const int _maxParallelism = 2 * recommendedParallelism;

  /// Argon2id memory in KiB for the files this instance seals.
  final int memoryKiB;

  /// Argon2id passes for the files this instance seals.
  final int iterations;

  /// Argon2id lanes for the files this instance seals.
  final int parallelism;

  /// Whether the work runs in a separate isolate. Off only in tests that need
  /// a deterministic, single-isolate run.
  final bool inIsolate;

  final Random _random;

  @override
  Future<Result<Uint8List, CommyFailure>> seal(
    Uint8List plain,
    String password,
  ) async {
    final header = _header(
      memoryKiB: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      salt: _bytes(_saltLength),
      nonce: _bytes(_nonceLength),
      // ChaCha20 keeps the length: the ciphertext is as long as the plain.
      length: plain.length,
    );
    try {
      final sealed = await _run(() => _sealWith(header, plain, password));
      return Ok(sealed);
    } on Object catch (error, stackTrace) {
      return Err(CommyFailure.fromCaught(error, stackTrace));
    }
  }

  @override
  Future<Result<Uint8List, CommyFailure>> open(
    Uint8List sealed,
    String password,
  ) async {
    final problem = inspect(sealed);
    if (problem != null) {
      return Err(BackupFailure(problem));
    }
    try {
      final plain = await _run(() => _openWith(sealed, password));
      if (plain == null) {
        return const Err(BackupFailure(BackupProblem.wrongPassword));
      }
      return Ok(plain);
    } on Object catch (error, stackTrace) {
      return Err(CommyFailure.fromCaught(error, stackTrace));
    }
  }

  @override
  BackupProblem? inspect(Uint8List sealed) {
    if (sealed.length < magic.length || sealed.length > maxFileBytes) {
      return BackupProblem.notABackup;
    }
    for (var i = 0; i < magic.length; i++) {
      if (sealed[i] != magic[i]) {
        return BackupProblem.notABackup;
      }
    }
    if (sealed.length < headerLength + _tagLength) {
      return BackupProblem.unreadable;
    }
    // A version, an algorithm or a flag this build does not know is a newer
    // Commy's file, and saying so sends the user to update rather than to
    // retype a password that was right.
    if (sealed[8] != containerVersion ||
        sealed[9] != _kdfArgon2id ||
        sealed[10] != _aeadChacha20Poly1305 ||
        sealed[11] != 0) {
      return BackupProblem.newerVersion;
    }
    final view = ByteData.sublistView(sealed);
    final memory = view.getUint32(12);
    final passes = view.getUint32(16);
    final lanes = sealed[20];
    final length = view.getUint32(52);
    final sane = headerLength + length + _tagLength <= sealed.length &&
        lanes >= 1 &&
        lanes <= _maxParallelism &&
        memory >= 8 * lanes &&
        memory <= _maxMemoryKiB &&
        passes >= 1 &&
        passes <= _maxIterations &&
        sealed[21] == _saltLength &&
        sealed[22] == _nonceLength &&
        sealed[23] == 0;
    return sane ? null : BackupProblem.unreadable;
  }

  Future<T> _run<T>(Future<T> Function() work) =>
      inIsolate ? Isolate.run(work) : work();

  Uint8List _bytes(int length) => Uint8List.fromList(
        List<int>.generate(length, (_) => _random.nextInt(256)),
      );

  static Uint8List _header({
    required int memoryKiB,
    required int iterations,
    required int parallelism,
    required Uint8List salt,
    required Uint8List nonce,
    required int length,
  }) {
    final header = Uint8List(headerLength)..setRange(0, magic.length, magic);
    ByteData.sublistView(header)
      ..setUint8(8, containerVersion)
      ..setUint8(9, _kdfArgon2id)
      ..setUint8(10, _aeadChacha20Poly1305)
      ..setUint8(11, 0)
      ..setUint32(12, memoryKiB)
      ..setUint32(16, iterations)
      ..setUint8(20, parallelism)
      ..setUint8(21, _saltLength)
      ..setUint8(22, _nonceLength)
      ..setUint8(23, 0)
      ..setUint32(52, length);
    header
      ..setRange(24, 24 + _saltLength, salt)
      ..setRange(40, 40 + _nonceLength, nonce);
    return header;
  }

  /// Runs in the worker isolate: everything it needs arrives as arguments.
  static Future<Uint8List> _sealWith(
    Uint8List header,
    Uint8List plain,
    String password,
  ) async {
    final key = await _derive(header, password);
    final box = await const DartChacha20.poly1305Aead().encrypt(
      plain,
      secretKey: key,
      nonce: header.sublist(40, 40 + _nonceLength),
      aad: header,
    );
    key.destroy();
    final end = headerLength + box.cipherText.length;
    return Uint8List(end + _tagLength)
      ..setRange(0, headerLength, header)
      ..setRange(headerLength, end, box.cipherText)
      ..setRange(end, end + _tagLength, box.mac.bytes);
  }

  /// Runs in the worker isolate. Null when the tag does not verify: a wrong
  /// password and a changed file are the same answer.
  static Future<Uint8List?> _openWith(Uint8List sealed, String password) async {
    final header = sealed.sublist(0, headerLength);
    final end = headerLength + ByteData.sublistView(header).getUint32(52);
    final key = await _derive(header, password);
    final box = SecretBox(
      sealed.sublist(headerLength, end),
      nonce: header.sublist(40, 40 + _nonceLength),
      mac: Mac(sealed.sublist(end, end + _tagLength)),
    );
    try {
      final plain = await const DartChacha20.poly1305Aead().decrypt(
        box,
        secretKey: key,
        aad: header,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      return null;
    } finally {
      key.destroy();
    }
  }

  static Future<SecretKeyData> _derive(
    Uint8List header,
    String password,
  ) async {
    final view = ByteData.sublistView(header);
    final kdf = DartArgon2id(
      memory: view.getUint32(12),
      iterations: view.getUint32(16),
      parallelism: header[20],
      hashLength: _keyLength,
    );
    // UTF-8 as typed: no trimming, no normalisation. A password is whatever
    // bytes the user's keyboard produced, and changing them here would lock
    // out the one person who knows it.
    final key = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: header.sublist(24, 24 + _saltLength),
    );
    return SecretKeyData(await key.extractBytes());
  }
}
