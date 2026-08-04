import 'dart:math';

import 'package:commy_domain/commy_domain.dart';

/// A UUID v4 source built on the platform CSPRNG.
///
/// commy_domain declares `IdGenerator` as a port precisely so no package in the
/// dependency graph has to pull a uuid library in; sixteen random bytes and two
/// masked nibbles are the whole of RFC 4122 §4.4.
class RandomIdGenerator implements IdGenerator {
  /// Creates a generator.
  ///
  /// [random] exists for tests that need reproducible identifiers. Production
  /// code always leaves it out and gets `Random.secure`.
  RandomIdGenerator({Random? random}) : _random = random ?? Random.secure();

  static const int _byteCount = 16;
  static const int _byteCeiling = 256;

  final Random _random;

  @override
  String newId() {
    final bytes = List<int>.generate(
      _byteCount,
      (_) => _random.nextInt(_byteCeiling),
      growable: false,
    );
    // Version 4 in the high nibble of byte 6, variant 1 in byte 8.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hex = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        hex.write('-');
      }
      hex.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }
}
