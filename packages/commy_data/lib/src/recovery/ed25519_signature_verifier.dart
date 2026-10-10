import 'package:commy_domain/commy_domain.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Ed25519 on the `cryptography` package the backup already carries, so the
/// recovery manifests of docs/adr/0019-subscription-domain-recovery.md cost
/// the APK nothing (rule R11).
///
/// The pure-Dart implementation, explicitly: the platform one would be a
/// plugin and a native dependency for a check that runs a few times a day
/// on a hundred bytes.
class Ed25519SignatureVerifier implements SignatureVerifier {
  /// Creates the verifier.
  const Ed25519SignatureVerifier();

  static final DartEd25519 _algorithm = DartEd25519();

  @override
  Future<bool> verifyEd25519({
    required List<int> publicKey,
    required List<int> message,
    required List<int> signature,
  }) async {
    if (publicKey.length != 32 || signature.length != 64) {
      return false;
    }
    try {
      return await _algorithm.verify(
        message,
        signature: Signature(
          signature,
          publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }
}
