import 'package:commy_data/src/http/commy_http_client.dart';
import 'package:commy_domain/commy_domain.dart';

/// Asks a provider's meeting point for its latest recovery manifest —
/// exception E-4 (docs/09-security-privacy.md,
/// docs/adr/0019-subscription-domain-recovery.md).
///
/// Everything about the request is chosen to say as little as possible:
///
/// * no `x-hwid`, no device headers, no cookies — none of the identity a
///   subscription host gets (ADR-0009). The meeting point learns the IP, the
///   provider's project from the path and that this is Commy, and nothing
///   else;
/// * around the tunnel, like a subscription refresh: the point is asked when
///   the subscription's own address is dead, which is exactly when there may
///   be no working tunnel to go through;
/// * a manifest is a few hundred bytes, so anything larger than [maxBytes]
///   is refused rather than read.
///
/// What comes back is not believed here. `ManifestReader` checks it against
/// the provider's pinned key; this class only carries it.
class HttpRendezvousFetcher implements RendezvousFetcher {
  /// Creates the fetcher.
  const HttpRendezvousFetcher({required CommyHttpClient client})
      : _client = client;

  /// The longest answer read, in characters — the format's own limit with
  /// room for a trailing newline.
  static const int maxBytes = SignedManifest.maxLength + 16;

  final CommyHttpClient _client;

  @override
  Future<Result<String, CommyFailure>> fetch(Uri url) async {
    if (url.scheme.toLowerCase() != 'https') {
      return Err<String, CommyFailure>(
        CommyFailure.subscriptionMalformed(
          'meeting point is not https: ${url.scheme}',
        ),
      );
    }
    final response = await _client.fetchText(url, throughTunnel: false);
    return response.flatMap((value) {
      final body = value.body.trim();
      if (body.isEmpty || body.length > maxBytes) {
        return const Err<String, CommyFailure>(
          CommyFailure.subscriptionMalformed('meeting point answer refused'),
        );
      }
      return Ok<String, CommyFailure>(body);
    });
  }
}
