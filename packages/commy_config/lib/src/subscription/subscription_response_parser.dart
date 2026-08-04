import 'package:commy_config/src/subscription/subscription_body_reader.dart';
import 'package:commy_config/src/subscription/subscription_headers.dart';
import 'package:commy_config/src/subscription/subscription_parse_result.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads a whole subscription response: body and headers together.
///
/// Panels put the node list in the body and everything else in the headers —
/// quota, expiry, display name, refresh interval, provider page
/// (docs/06-data-model.md). Splitting the two across layers means the caller
/// has to remember to parse both, so they are parsed in one call here.
///
/// Header names are matched case-insensitively; no two panels agree on the
/// casing and the HTTP specification says they do not have to.
class SubscriptionResponseParser {
  /// Creates a parser over [reader].
  SubscriptionResponseParser({SubscriptionBodyReader? reader})
      : _reader = reader ?? SubscriptionBodyReader();

  final SubscriptionBodyReader _reader;

  /// Parses a response.
  ///
  /// [headers] takes the map an HTTP client hands back, where a value may be
  /// either a single string or a list of them.
  SubscriptionParseResult parse({
    required String body,
    Map<String, Object?> headers = const <String, Object?>{},
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) {
    final parsed = SubscriptionHeaders.from(headers);
    return SubscriptionParseResult(
      payload: parsed.toPayload(body),
      outcome: _reader.read(
        body,
        subscriptionId: subscriptionId,
        groupId: groupId,
        startIndex: startIndex,
      ),
      announcement: parsed.announcement,
    );
  }

  /// Parses a payload that some other layer already fetched.
  ///
  /// This is the path `UpdateSubscriptionUseCase` takes: the fetcher owns the
  /// HTTP call and hands the domain a `SubscriptionPayload`.
  SubscriptionParseResult parsePayload(
    SubscriptionPayload payload, {
    String? subscriptionId,
    String? groupId,
    int startIndex = 0,
  }) =>
      SubscriptionParseResult(
        payload: payload,
        outcome: _reader.read(
          payload.body,
          subscriptionId: subscriptionId,
          groupId: groupId,
          startIndex: startIndex,
        ),
      );
}
