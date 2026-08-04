import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:commy_core/src/clash/clash_codec.dart';
import 'package:commy_core/src/clash/clash_endpoint.dart';
import 'package:commy_core/src/core_client_exception.dart';
import 'package:commy_core/src/logging/app_logger.dart';
import 'package:commy_core/src/wire/url_test_codec.dart';
import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_domain/commy_domain.dart';

/// The data half of the desktop core transport: sing-box's Clash API.
///
/// ## Do not wire this up on Android or iOS
///
/// Mobile uses libbox's `CommandClient` through the platform channels in
/// `lib/src/android/` — see `docs/wire-protocol.md`. The Clash API is an HTTP
/// server *inside the process that carries the tunnel*, which on iOS means
/// inside a Network Extension with a 50 MiB ceiling (rule R7) and on both
/// platforms means one more listening socket than the app needs. ADR-0005 says
/// mobile does not raise it, `SingBoxConfigBuilder` only emits the
/// `experimental.clash_api` section when asked, and `ConnectUseCase` only asks
/// on desktop. If this class ever appears in a mobile composition root, that is
/// the bug — not a configuration choice.
///
/// ## What this is and is not
///
/// This is *half* of a desktop `CoreClient`. The Clash API can list proxies,
/// switch between them, measure one, and stream traffic, logs and connections.
/// It cannot start or stop the core: on Windows, Linux and macOS-outside-the-
/// store the core lives in a privileged process, and raising it is the job of
/// the control channel to that helper. Those helpers are later milestones, so
/// the class deliberately does not implement `CoreClient` — a client whose
/// `start` throws is a trap for whoever wires it up next.
///
/// ## Rule R1
///
/// Every request goes to [ClashEndpoint.base], which is loopback. Nothing here
/// reaches a host the user did not configure, and there is no code path to one.
class ClashApiClient {
  /// Creates a client against [endpoint].
  ///
  /// [httpClient] is injectable so a test can point it at a real loopback
  /// server; the default is a plain [HttpClient] with no proxy resolution.
  ClashApiClient({
    required ClashEndpoint endpoint,
    AppLogger? logger,
    HttpClient? httpClient,
    Duration urlTestTimeout = UrlTestCodec.defaultTimeout,
  })  : _endpoint = endpoint,
        _logger = logger,
        _http = httpClient ?? (HttpClient()..findProxy = _noProxy),
        _urlTestTimeout = urlTestTimeout;

  /// Tag the client's own log lines carry.
  static const String logTag = 'core.clash';

  /// Status codes that mean "the probe did not come back", not "we broke".
  static const Set<int> probeTimeoutCodes = <int>{408, 502, 503, 504};

  final ClashEndpoint _endpoint;
  final AppLogger? _logger;
  final HttpClient _http;
  final Duration _urlTestTimeout;

  int _uplinkTotal = 0;
  int _downlinkTotal = 0;
  bool _disposed = false;

  /// The endpoint this client talks to.
  ClashEndpoint get endpoint => _endpoint;

  /// Lists the outbound groups the core knows about.
  Future<List<ProxyGroup>> proxies() async {
    final body = await _json(_endpoint.proxies);
    return ClashCodec.decodeProxies(body);
  }

  /// Points the group tagged [group] at the member tagged [tag].
  Future<void> select(String group, String tag) async {
    await _send(
      method: 'PUT',
      uri: _endpoint.proxyGroup(group),
      body: jsonEncode(<String, Object?>{'name': tag}),
    );
  }

  /// Measures the round trip of [tag] against [probe].
  ///
  /// A timeout answers `null` rather than throwing: an unreachable node has to
  /// stay distinguishable from a broken app, which is why
  /// `MeasureLatencyUseCase` treats `null` as a success.
  Future<Duration?> urlTest(String tag, Uri probe) async {
    final uri = _endpoint.delay(
      tag,
      probe: probe,
      timeout: _urlTestTimeout,
    );
    final response = await _open('GET', uri);
    if (probeTimeoutCodes.contains(response.statusCode)) {
      await response.drain<void>();
      return null;
    }
    final body = await _bodyOf(response, uri);
    return ClashCodec.decodeDelay(body);
  }

  /// Throughput ticks, one per second while the core is up.
  ///
  /// The stream ends when the core closes the response. Reconnecting is the
  /// caller's decision, because "the core went away" is a state the tunnel
  /// screen has to show rather than paper over.
  Stream<TrafficSample> get traffic => _lines(_endpoint.traffic).map(
        (json) => ClashCodec.decodeTraffic(
          json,
          uplinkTotal: _uplinkTotal,
          downlinkTotal: _downlinkTotal,
        ),
      );

  /// Core log lines, raw. Redaction happens in `AppLogger`, one layer up.
  Stream<LogLine> logs({LogLevel level = LogLevel.info}) =>
      _lines(_endpoint.logs(level: level)).map(ClashCodec.decodeLog);

  /// Snapshots of the open connections.
  ///
  /// Also the only place the Clash API reports cumulative byte counters, so
  /// each snapshot updates the totals that [traffic] attaches to its ticks.
  Stream<List<ConnectionInfo>> get connections =>
      _lines(_endpoint.connections).map((json) {
        final snapshot = ClashCodec.decodeConnections(json);
        _uplinkTotal = snapshot.uplinkTotal;
        _downlinkTotal = snapshot.downlinkTotal;
        return snapshot.connections;
      });

  /// Closes the underlying HTTP client and every stream hanging off it.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _http.close(force: true);
  }

  Future<Object?> _json(Uri uri) async {
    final response = await _open('GET', uri);
    return _bodyOf(response, uri);
  }

  Future<void> _send({
    required String method,
    required Uri uri,
    String? body,
  }) async {
    final response = await _open(method, uri, body: body);
    await _bodyOf(response, uri, allowEmpty: true);
  }

  Future<HttpClientResponse> _open(
    String method,
    Uri uri, {
    String? body,
  }) async {
    try {
      final request = await _http.openUrl(method, uri);
      _endpoint.headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      return await request.close();
    } on Object catch (error, stackTrace) {
      // A refused connection means the helper is not there. That is the whole
      // diagnosis the user needs, and it is actionable.
      _logger?.warn('${uri.path}: transport failed', tag: logTag);
      throw CoreClientException(
        error is SocketException || error is HttpException
            ? const HelperUnavailableFailure()
            : UnknownFailure(error, stackTrace),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<Object?> _bodyOf(
    HttpClientResponse response,
    Uri uri, {
    bool allowEmpty = false,
  }) async {
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw CoreClientException(_failureFor(response.statusCode, text, uri));
    }
    if (text.trim().isEmpty) {
      if (allowEmpty) {
        return null;
      }
      throw CoreClientException(
        UnknownFailure('${uri.path}: empty body', StackTrace.empty),
      );
    }
    return text;
  }

  CommyFailure _failureFor(int status, String body, Uri uri) {
    final message = _messageOf(body);
    _logger?.warn('${uri.path}: HTTP $status', tag: logTag);
    return switch (status) {
      // No token, or the wrong one. From where the user sits the control
      // channel is simply not available.
      401 || 403 => const HelperUnavailableFailure(),
      404 => ConfigInvalidFailure(
          message.isEmpty ? 'No such outbound or group' : message,
        ),
      _ => UnknownFailure('HTTP $status: $message', StackTrace.empty),
    };
  }

  String _messageOf(String body) {
    try {
      final json = WireJson.object(body, 'error body');
      return WireJson.stringOr(json, 'message', orElse: '');
    } on Object {
      return body.trim();
    }
  }

  Stream<JsonMap> _lines(Uri uri) async* {
    final response = await _open('GET', uri);
    if (response.statusCode >= 400) {
      await _bodyOf(response, uri);
      return;
    }
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty);
    await for (final line in lines) {
      try {
        yield WireJson.object(line, '${uri.path} line');
      } on Object catch (error) {
        _logger?.warn(
          '${uri.path}: dropped a malformed line',
          tag: logTag,
          error: error,
        );
      }
    }
  }

  static String _noProxy(Uri uri) => 'DIRECT';
}
