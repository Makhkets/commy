import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';

/// Builds the stable identifier of a parsed node.
///
/// The identifier is a hash of what makes a server *that* server: protocol,
/// address, port and credential, plus the handful of transport fields that
/// can make two entries on the same address genuinely different endpoints.
///
/// The display name is deliberately **not** part of it. Panels rename nodes
/// constantly, and an identifier that changes on rename throws away the
/// measured latency and the user's manual grouping on every refresh.
///
/// Two entries that differ only by name therefore collapse into one node.
/// That is the intended behaviour: they are the same server.
abstract final class NodeIdFactory {
  /// Params that take part in the identity of a node.
  ///
  /// Everything else — names, declared bandwidth, cosmetic flags — can change
  /// between refreshes without meaning a different server.
  static const List<String> identityParams = <String>[
    'uuid',
    'password',
    'method',
    'type',
    'security',
    'path',
    'serviceName',
    'private_key',
    'peerPublicKey',
    'username',
  ];

  /// 32-bit FNV-1a offset basis.
  static const int fnvOffset = 0x811C9DC5;

  /// 32-bit FNV-1a prime.
  static const int fnvPrime = 0x01000193;

  /// Builds the identifier of a node.
  static String forNode({
    required Protocol protocol,
    required String host,
    required int port,
    required Map<String, Object?> params,
  }) {
    final buffer = StringBuffer()
      ..write(protocol.wireName)
      ..write('|')
      ..write(host.toLowerCase())
      ..write('|')
      ..write(port);
    for (final key in identityParams) {
      final value = params[key];
      if (value != null && '$value'.isNotEmpty) {
        buffer
          ..write('|')
          ..write(key)
          ..write('=')
          ..write(value);
      }
    }
    return digest(buffer.toString());
  }

  /// Sixteen hexadecimal characters derived from [source].
  ///
  /// Two 32-bit FNV-1a passes, forwards and backwards, rather than one 64-bit
  /// pass. Every intermediate value is masked back to 32 bits, so the result
  /// never depends on how wide the platform's integers happen to be — which
  /// is what makes the golden tests reproducible.
  ///
  /// This is a bucketing hash, not a cryptographic one. It guards nothing.
  static String digest(String source) {
    final bytes = utf8.encode(source);
    final head = _fnv1a(bytes, fnvOffset);
    final tail = _fnv1a(bytes.reversed.toList(), fnvOffset ^ 0x5BF03635);
    return '${_hex(head)}${_hex(tail)}';
  }

  /// The FNV-1a prime `0x01000193` decomposed into shifts.
  ///
  /// `0x01000193 == 2^24 + 2^8 + 2^7 + 2^4 + 2^1 + 2^0`. Multiplying by hand
  /// keeps every intermediate value inside 32 bits instead of relying on a
  /// 64-bit multiply wrapping the way the VM happens to wrap it.
  static const List<int> primeShifts = <int>[1, 4, 7, 8, 24];

  static int _fnv1a(List<int> bytes, int seed) {
    var hash = seed & 0xFFFFFFFF;
    for (final byte in bytes) {
      hash = (hash ^ byte) & 0xFFFFFFFF;
      var sum = hash;
      for (final shift in primeShifts) {
        sum = (sum + ((hash << shift) & 0xFFFFFFFF)) & 0xFFFFFFFF;
      }
      hash = sum;
    }
    return hash;
  }

  static String _hex(int value) => value.toRadixString(16).padLeft(8, '0');
}
