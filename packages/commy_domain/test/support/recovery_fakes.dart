import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';

/// A 32-byte "key" for tests, base64url without padding.
String testKey([int seed = 7]) =>
    base64Url.encode(List<int>.filled(32, seed)).replaceAll('=', '');

/// A manifest payload with sensible defaults, as a provider would sign it.
Map<String, Object?> manifestJson({
  String id = 'axm',
  int seq = 1,
  int iat = 1791160000,
  String origin = 'https://sub.example.com',
  List<String> mirrors = const <String>['https://mirror.example.org'],
  List<String> rendezvous = const <String>['https://meet.example.net/r/axm'],
  String? key,
  String? nextKey,
  String? name = 'AXM VPN',
}) =>
    <String, Object?>{
      'v': 1,
      'id': id,
      'seq': seq,
      'iat': iat,
      'origin': origin,
      'mirrors': mirrors,
      'rendezvous': rendezvous,
      'key': key ?? testKey(),
      if (nextKey != null) 'next_key': nextKey,
      if (name != null) 'name': name,
    };

/// [payload] in the compact form. The signature is 64 bytes of [signature]:
/// [FakeVerifier] calls `1` valid and anything else forged.
String compactOf(Map<String, Object?> payload, {int signature = 1}) {
  String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  return 'v1.${b64(utf8.encode(jsonEncode(payload)))}'
      '.${b64(List<int>.filled(64, signature))}';
}

/// Accepts a signature of all ones, and records what it was asked.
class FakeVerifier implements SignatureVerifier {
  /// Every verification asked for, as the key it named.
  final List<List<int>> asked = <List<int>>[];

  @override
  Future<bool> verifyEd25519({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  }) async {
    asked.add(publicKey);
    return signature.every((byte) => byte == 1);
  }
}

/// Serves a manifest per meeting point, and records the visits.
class FakeRendezvous implements RendezvousFetcher {
  /// What each point serves; a point not here fails.
  final Map<Uri, String> served = <Uri, String>{};

  /// The points asked, in order.
  final List<Uri> visits = <Uri>[];

  @override
  Future<Result<String, CommyFailure>> fetch(Uri url) async {
    visits.add(url);
    final body = served[url];
    if (body == null) {
      return Err<String, CommyFailure>(
        SubscriptionUnreachableFailure(url: url, cause: 'no answer'),
      );
    }
    return Ok<String, CommyFailure>(body);
  }
}
