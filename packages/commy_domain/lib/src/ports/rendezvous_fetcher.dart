import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';

/// Asks a provider's meeting point for its latest recovery manifest
/// (exception E-4, docs/adr/0019-subscription-domain-recovery.md).
///
/// The only request the client makes to a host the user never typed and the
/// subscription's own address did not answer from, so the implementation
/// carries nothing that identifies the user: no `x-hwid` or device headers,
/// no cookies, no token, the honest `Commy/<version>` and nothing else. What
/// comes back is checked by its signature, not by where it came from.
abstract interface class RendezvousFetcher {
  /// The manifest [url] serves, in its compact form, unchecked.
  Future<Result<String, CommyFailure>> fetch(Uri url);
}
