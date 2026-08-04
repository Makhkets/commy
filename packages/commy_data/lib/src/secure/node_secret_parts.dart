import 'package:commy_domain/commy_domain.dart';

/// A node's protocol parameters, split into what may be stored and what may
/// not.
///
/// `ProxyNode.params` is one flat map holding both the harmless (`sni`, `fp`,
/// `alpn`, `path`) and the fatal (`uuid`, `password`, `private_key`). The
/// database only ever sees [public]; [secret] goes to the keystore under a key
/// the row points at. That split is rule R2, and
/// `ProxyNode.secretParamKeys` is the single list both sides key off.
class NodeSecretParts {
  /// Creates a split. Prefer [NodeSecretParts.of].
  const NodeSecretParts({required this.public, required this.secret});

  /// Splits [params] by `ProxyNode.secretParamKeys`.
  ///
  /// Matching is case-insensitive because real subscriptions spell the same
  /// field `uuid`, `UUID` and `Uuid` in the same document.
  factory NodeSecretParts.of(Map<String, Object?> params) {
    final public = <String, Object?>{};
    final secret = <String, Object?>{};
    for (final entry in params.entries) {
      if (isSecretKey(entry.key)) {
        secret[entry.key] = entry.value;
      } else {
        public[entry.key] = entry.value;
      }
    }
    return NodeSecretParts(public: public, secret: secret);
  }

  /// Parameters safe to keep in a plain column.
  final Map<String, Object?> public;

  /// Parameters that only ever live in the secure store.
  final Map<String, Object?> secret;

  /// Whether this node has anything worth protecting at all.
  ///
  /// A `socks` node without a password has not, and gets no keystore entry —
  /// one less thing to leak and one less round trip on every read.
  bool get hasSecret => secret.isNotEmpty;

  /// Whether [key] names a credential.
  static bool isSecretKey(String key) =>
      ProxyNode.secretParamKeys.contains(key.toLowerCase());

  /// Puts a split map back together.
  ///
  /// [secret] wins on a collision: a stale public copy of a credential (which
  /// should never exist, but might after a botched migration) must not shadow
  /// the real one.
  static Map<String, Object?> merge(
    Map<String, Object?> public,
    Map<String, Object?> secret,
  ) =>
      <String, Object?>{...public, ...secret};
}
