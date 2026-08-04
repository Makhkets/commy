/// A text response, headers and all.
///
/// The headers are the point. Panels put the quota, the expiry, the profile
/// name and the suggested refresh interval into `subscription-userinfo`,
/// `profile-title` and friends — the body is just a list of links
/// (docs/06-data-model.md, "Заголовки ответа подписки"). A client that
/// swallowed the headers would make that data unreachable, so this type carries
/// them across the package boundary untouched, and commy_config decides what
/// they mean.
class HttpTextResponse {
  /// Creates a response.
  const HttpTextResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.url,
  });

  /// HTTP status the server answered with.
  final int statusCode;

  /// Decoded body.
  final String body;

  /// Response headers, lowercase names, values in arrival order.
  final Map<String, List<String>> headers;

  /// The URL the response finally came from, after redirects.
  ///
  /// A panel that redirects `/sub/token` to a CDN is common; knowing where the
  /// bytes actually came from is what makes such a case debuggable.
  final Uri url;

  /// The first value of [name], or `null`.
  String? header(String name) {
    final values = headers[name.trim().toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  /// Headers in the shape a header parser expects.
  ///
  /// Single-element lists collapse to their value, so a parser that accepts
  /// `String` or `List<String>` — such as `SubscriptionHeaders.from` — gets
  /// what it wants either way.
  Map<String, Object?> get headerValues => <String, Object?>{
        for (final entry in headers.entries)
          entry.key: entry.value.length == 1 ? entry.value.first : entry.value,
      };

  /// Never prints [body]: a subscription body is a list of live credentials.
  @override
  String toString() => 'HttpTextResponse($statusCode, ${body.length} bytes, '
      '${headers.length} headers)';
}
