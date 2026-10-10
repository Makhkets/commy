import 'package:commy_domain/src/entities/recovery_manifest.dart';
import 'package:commy_domain/src/entities/subscription_recovery.dart';
import 'package:commy_domain/src/ports/signature_verifier.dart';

/// Turns a compact manifest from the network into a [RecoveryManifest] the
/// client may act on, or nothing.
///
/// Three checks, in this order, each one enough to drop the manifest:
///
/// 1. its shape and every limit of the format ([SignedManifest.parse]);
/// 2. when the subscription has a pinned key, that the manifest belongs to
///    the same project and is signed by that key — or by the next one the
///    pinned key announced;
/// 3. the Ed25519 signature itself.
///
/// The second check runs before the third on purpose: a manifest signed by
/// a stranger is refused without spending a verification on it.
class ManifestReader {
  /// Creates the reader.
  const ManifestReader({required this.verifier});

  /// What checks the signatures.
  final SignatureVerifier verifier;

  /// The manifest in [compact], verified against [pinned]; `null` when there
  /// is none, or it is not to be believed.
  Future<RecoveryManifest?> read(
    String? compact, {
    SubscriptionRecovery? pinned,
  }) async {
    if (compact == null || compact.trim().isEmpty) {
      return null;
    }
    final signed = SignedManifest.parse(compact);
    if (signed == null) {
      return null;
    }
    final manifest = signed.manifest;
    if (pinned != null) {
      if (manifest.id != pinned.id) {
        return null;
      }
      if (manifest.key != pinned.key && manifest.key != pinned.nextKey) {
        return null;
      }
    }
    final valid = await verifier.verifyEd25519(
      publicKey: signed.publicKey,
      message: signed.signedBytes,
      signature: signed.signature,
    );
    return valid ? manifest : null;
  }
}
