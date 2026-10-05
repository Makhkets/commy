/// Checks Ed25519 signatures (RFC 8032).
///
/// A port because the domain has no cryptography of its own and must not
/// grow any (rule R5, docs/adr/0006-codegen-and-native-layout.md): the data
/// layer implements it on the `cryptography` package it already carries for
/// backups. It is what stands between a recovery manifest from the network
/// and an address the client will talk to
/// (docs/adr/0019-subscription-domain-recovery.md).
abstract interface class SignatureVerifier {
  /// Whether [signature] is a valid Ed25519 signature of [message] by
  /// [publicKey]. Never throws: a malformed key or signature is `false`.
  Future<bool> verifyEd25519({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  });
}
