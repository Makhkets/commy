import 'package:commy_data/src/http/commy_http_client.dart';
import 'package:commy_domain/commy_domain.dart';

/// Turns a response body and its headers into a payload.
///
/// A function rather than an interface so that commy_data does not have to know
/// how a `subscription-userinfo` header is spelled. Parsing lives in
/// commy_config, and the dependency graph only allows commy_data → commy_domain
/// (CLAUDE.md §3), so the composition root wires the two together:
///
/// ```dart
/// HttpSubscriptionFetcher(
///   client: httpClient,
///   payloadMapper: (body, headers) =>
///       SubscriptionHeaders.from(headers).toPayload(body),
/// );
/// ```
typedef SubscriptionPayloadMapper = SubscriptionPayload Function(
  String body,
  Map<String, Object?> headers,
);

/// Downloads a subscription document over HTTP.
///
/// The one network call the app makes on its own behalf, and it goes to a host
/// the user typed in — rule R1 holds by construction.
///
/// Three things this implementation is careful about:
///
/// * **Direction.** `throughTunnel` is passed straight through with no default.
///   `AddSubscriptionUseCase` always passes `false`, because a fresh install
///   has no tunnel to route through.
/// * **Identification.** The honest `Commy/<version>` unless the subscription
///   carries an override the user set (docs/06-data-model.md, "User-Agent имеет
///   значение").
/// * **Trust.** An empty body, a body that is not text, or one larger than the
///   client's cap becomes a typed failure rather than something the parser has
///   to survive.
class HttpSubscriptionFetcher implements SubscriptionFetcher {
  /// Creates the fetcher.
  const HttpSubscriptionFetcher({
    required CommyHttpClient client,
    required SubscriptionPayloadMapper payloadMapper,
  })  : _client = client,
        _payloadMapper = payloadMapper;

  final CommyHttpClient _client;
  final SubscriptionPayloadMapper _payloadMapper;

  @override
  Future<Result<SubscriptionPayload, CommyFailure>> fetch(
    Uri url, {
    required bool throughTunnel,
    String? userAgent,
  }) async {
    final response = await _client.fetchText(
      url,
      throughTunnel: throughTunnel,
      userAgentOverride: userAgent,
    );

    return response.flatMap((value) {
      if (value.body.trim().isEmpty) {
        return const Err<SubscriptionPayload, CommyFailure>(
          CommyFailure.subscriptionMalformed('empty response body'),
        );
      }
      try {
        return Ok<SubscriptionPayload, CommyFailure>(
          _payloadMapper(value.body, value.headerValues),
        );
      } on Object catch (error) {
        return Err<SubscriptionPayload, CommyFailure>(
          CommyFailure.subscriptionMalformed(
            'could not read response headers: ${error.runtimeType}',
          ),
        );
      }
    });
  }
}
