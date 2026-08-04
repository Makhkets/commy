import 'package:commy_domain/commy_domain.dart';

/// Where the desktop core's Clash API lives, and how to be let in.
///
/// Loopback only, always with a token. The service writes the token to a file
/// only the current user can read and refuses every request without it
/// (ADR-0005). The token travels in the `Authorization` header and never in the
/// query string, so it cannot end up in a log line, a crash report or a shell
/// history.
class ClashEndpoint {
  /// Creates an endpoint at [base], authenticated with [secret].
  const ClashEndpoint({required this.base, this.secret});

  /// The usual case: `http://127.0.0.1:<port>`.
  factory ClashEndpoint.loopback({int port = defaultPort, String? secret}) =>
      ClashEndpoint(
        base: Uri(scheme: 'http', host: '127.0.0.1', port: port),
        secret: secret,
      );

  /// The port sing-box's Clash API listens on by default.
  static const int defaultPort = 9090;

  /// Root of the API, without a trailing path.
  final Uri base;

  /// The bearer token, or `null` while the service has not produced one.
  final String? secret;

  /// Headers every request carries.
  Map<String, String> get headers => <String, String>{
        'Accept': 'application/json',
        if (secret != null && secret!.isNotEmpty)
          'Authorization': 'Bearer $secret',
      };

  /// `GET /proxies` — every group and every outbound the core knows.
  Uri get proxies => _path(const <String>['proxies']);

  /// `PUT /proxies/{group}` — points a group at one of its members.
  Uri proxyGroup(String group) => _path(<String>['proxies', group]);

  /// `GET /proxies/{tag}/delay` — measures one outbound.
  Uri delay(
    String tag, {
    required Uri probe,
    required Duration timeout,
  }) =>
      _path(
        <String>['proxies', tag, 'delay'],
        <String, String>{
          'url': probe.toString(),
          'timeout': '${timeout.inMilliseconds}',
        },
      );

  /// `GET /traffic` — one JSON object per second.
  Uri get traffic => _path(const <String>['traffic']);

  /// `GET /logs` — one JSON object per line, at [level] and louder.
  Uri logs({LogLevel level = LogLevel.info}) => _path(
        const <String>['logs'],
        <String, String>{'level': level.wireName},
      );

  /// `GET /connections` — a full snapshot, repeated.
  Uri get connections => _path(const <String>['connections']);

  Uri _path(List<String> segments, [Map<String, String>? query]) {
    final merged = <String>[
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      ...segments,
    ];
    if (query == null) {
      return base.replace(pathSegments: merged);
    }
    return base.replace(pathSegments: merged, queryParameters: query);
  }

  /// Never prints [secret]: it is the key to the tunnel's control channel.
  @override
  String toString() {
    final auth = secret == null ? 'no secret' : Redact.placeholder;
    return 'ClashEndpoint($base, $auth)';
  }
}
