import 'dart:io';

import 'package:commy_data/src/http/http_text_response.dart';
import 'package:commy_data/src/http/network_failure_mapper.dart';
import 'package:commy_data/src/http/proxy_endpoint.dart';
import 'package:commy_data/src/http/user_agent.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// The only HTTP client in the app, and the only place a request can start.
///
/// Rule R1 is a property of what calls this class, not of the class itself, so
/// the rule is written down where it can be checked: the legitimate callers are
///
/// * `SubscriptionFetcher` — a host the user typed in;
/// * E-1, the external IP check, on an explicit button press, through the
///   tunnel, with the endpoint the user configured (empty by default);
/// * E-2, the geoip/geosite rule sets, on an explicit button press;
/// * E-3, the ad blocking lists, only while that feature is on.
///
/// There is no fifth caller, no analytics, no crash reporter and no update
/// check. Adding one is an owner decision (docs/09-security-privacy.md).
class CommyHttpClient {
  /// Creates the client.
  ///
  /// [tunnelProxy] is the local inbound the core exposes; without it a request
  /// asked to go `throughTunnel` falls back to a direct socket and relies on
  /// the platform tunnel capturing it, which is what happens on mobile anyway.
  ///
  /// [directClient] and [proxiedClient] exist for tests, which hand in a `Dio`
  /// carrying `DioAdapter` or a stub adapter.
  CommyHttpClient({
    this.userAgent = CommyUserAgent.fallback,
    this.tunnelProxy,
    this.connectTimeout = defaultConnectTimeout,
    this.receiveTimeout = defaultReceiveTimeout,
    this.sendTimeout = defaultSendTimeout,
    this.maxRedirects = defaultMaxRedirects,
    this.maxBodyBytes = defaultMaxBodyBytes,
    Dio? directClient,
    Dio? proxiedClient,
  })  : _injectedDirect = directClient,
        _injectedProxied = proxiedClient;

  /// How long a connection may take to establish.
  static const Duration defaultConnectTimeout = Duration(seconds: 15);

  /// How long the whole body may take to arrive.
  ///
  /// Generous: subscription panels are often small VPSes under load, and a
  /// refresh that fails at ten seconds is a support ticket.
  static const Duration defaultReceiveTimeout = Duration(seconds: 30);

  /// How long sending the request may take.
  static const Duration defaultSendTimeout = Duration(seconds: 15);

  /// How many redirects to follow.
  ///
  /// Panels redirect: `/sub/token` to a CDN, http to https, a short link to the
  /// real one. Five is plenty and stops a redirect loop from hanging the app.
  static const int defaultMaxRedirects = 5;

  /// Largest body we are willing to hold in memory.
  ///
  /// A subscription is a text file; eight megabytes is already a hundred
  /// thousand links. The cap exists because the response comes from a server we
  /// do not control and "zero trust to the input" includes its length
  /// (docs/06-data-model.md, "Правила парсера", rule 3).
  static const int defaultMaxBodyBytes = 8 * 1024 * 1024;

  /// Schemes a fetch may use. Anything else is refused before a socket opens.
  static const Set<String> allowedSchemes = <String>{'http', 'https'};

  /// Identification sent unless a call overrides it.
  final String userAgent;

  /// Local inbound used when a request must go through the tunnel.
  final ProxyEndpoint? tunnelProxy;

  /// Connection timeout.
  final Duration connectTimeout;

  /// Receive timeout.
  final Duration receiveTimeout;

  /// Send timeout.
  final Duration sendTimeout;

  /// Redirect budget.
  final int maxRedirects;

  /// Body size cap in bytes.
  final int maxBodyBytes;

  final Dio? _injectedDirect;
  final Dio? _injectedProxied;

  Dio? _direct;
  Dio? _proxied;

  /// Fetches [url] as text, keeping the response headers.
  ///
  /// [throughTunnel] has no default here for the same reason it has none on
  /// `SubscriptionFetcher`: which side of the tunnel a request leaves on is a
  /// decision worth writing down at every call site.
  Future<Result<HttpTextResponse, CommyFailure>> fetchText(
    Uri url, {
    required bool throughTunnel,
    String? userAgentOverride,
    Map<String, String> extraHeaders = const <String, String>{},
    CancelToken? cancelToken,
  }) async {
    if (!allowedSchemes.contains(url.scheme.toLowerCase())) {
      return Err<HttpTextResponse, CommyFailure>(
        CommyFailure.subscriptionMalformed(
          'unsupported URL scheme: ${url.scheme}',
        ),
      );
    }

    final client = throughTunnel ? _proxiedDio() : _directDio();
    try {
      final response = await client.getUri<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: maxRedirects,
          // Repeated per request, not just on the base options, so that an
          // injected `Dio` — a test double, or a future adapter — cannot end
          // up without a deadline and hang the refresh forever.
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          headers: <String, String>{
            HttpHeaders.userAgentHeader: userAgentOverride ?? userAgent,
            HttpHeaders.acceptHeader: '*/*',
            ...extraHeaders,
          },
          // 3xx is followed by dio itself; anything at or above 400 is an
          // error we want to see as one.
          validateStatus: (status) => status != null && status < 400,
        ),
        cancelToken: cancelToken,
      );

      final body = response.data ?? '';
      if (body.length > maxBodyBytes) {
        return Err<HttpTextResponse, CommyFailure>(
          NetworkFailureMapper.tooLarge(url, maxBodyBytes),
        );
      }

      return Ok<HttpTextResponse, CommyFailure>(
        HttpTextResponse(
          statusCode: response.statusCode ?? 0,
          body: body,
          headers: _normaliseHeaders(response.headers),
          url: response.realUri,
        ),
      );
    } on DioException catch (error) {
      return Err<HttpTextResponse, CommyFailure>(
        NetworkFailureMapper.fromDio(error, url),
      );
    } on Object catch (error) {
      return Err<HttpTextResponse, CommyFailure>(
        NetworkFailureMapper.fromError(error, url),
      );
    }
  }

  /// Closes both underlying clients.
  void close({bool force = false}) {
    _direct?.close(force: force);
    _proxied?.close(force: force);
    _direct = null;
    _proxied = null;
  }

  static Map<String, List<String>> _normaliseHeaders(Headers headers) {
    final result = <String, List<String>>{};
    headers.forEach((name, values) {
      result[name.trim().toLowerCase()] = List<String>.unmodifiable(values);
    });
    return result;
  }

  Dio _directDio() => _direct ??= _injectedDirect ?? _build(proxy: null);

  Dio _proxiedDio() {
    final proxy = tunnelProxy;
    if (proxy == null) {
      // No local inbound to aim at. The request goes out on a plain socket and
      // the platform tunnel decides its fate, which is the honest behaviour on
      // mobile — there is nothing else a userspace HTTP client can do there.
      return _directDio();
    }
    return _proxied ??= _injectedProxied ?? _build(proxy: proxy);
  }

  Dio _build({required ProxyEndpoint? proxy}) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        followRedirects: true,
        maxRedirects: maxRedirects,
        responseType: ResponseType.plain,
        headers: <String, String>{
          HttpHeaders.userAgentHeader: userAgent,
        },
      ),
    );
    if (proxy != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => HttpClient()
          ..findProxy = ((_) => proxy.proxyDirective)
          ..connectionTimeout = connectTimeout,
      );
    }
    return dio;
  }
}
