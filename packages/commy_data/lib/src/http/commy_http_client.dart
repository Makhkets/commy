import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
    this.totalTimeout = defaultTotalTimeout,
    this.maxRedirects = defaultMaxRedirects,
    this.maxBodyBytes = defaultMaxBodyBytes,
    Dio? directClient,
    Dio? proxiedClient,
  })  : _injectedDirect = directClient,
        _injectedProxied = proxiedClient;

  /// How long a connection may take to establish.
  static const Duration defaultConnectTimeout = Duration(seconds: 15);

  /// How long the server may go quiet: before the headers, and between two
  /// chunks of the body.
  ///
  /// Generous: subscription panels are often small VPSes under load, and a
  /// refresh that fails at ten seconds is a support ticket. It is not a limit
  /// on the whole body — dio restarts it on every chunk — which is what
  /// [defaultTotalTimeout] is for.
  static const Duration defaultReceiveTimeout = Duration(seconds: 30);

  /// How long sending the request may take.
  static const Duration defaultSendTimeout = Duration(seconds: 15);

  /// How long one fetch may take from start to last byte.
  ///
  /// A server that sends a byte every twenty seconds never trips
  /// [defaultReceiveTimeout], and a fetch that never ends is worse than one
  /// that fails: `SubscriptionController` serves one refresh at a time and the
  /// schedulers sweep in sequence, so it stopped every other refresh until the
  /// app was restarted. Two minutes carries a full [defaultMaxBodyBytes] body
  /// over a slow line and still hands the refresh back.
  static const Duration defaultTotalTimeout = Duration(minutes: 2);

  /// How many redirects to follow.
  ///
  /// Panels redirect: `/sub/token` to a CDN, http to https, a short link to the
  /// real one. Five is plenty and stops a redirect loop from hanging the app.
  ///
  /// They are followed here, hop by hop, not by `dart:io`: it copies every
  /// header but the credentials it knows about to wherever `Location` points,
  /// and it follows https to plain http without a word.
  static const int defaultMaxRedirects = 5;

  /// Statuses that send the request on to `Location`, as `dart:io` has them.
  static const Set<int> redirectStatuses = <int>{301, 302, 303, 307, 308};

  /// Largest body we are willing to hold in memory.
  ///
  /// A subscription is a text file; eight megabytes is already a hundred
  /// thousand links. The cap exists because the response comes from a server we
  /// do not control and "zero trust to the input" includes its length
  /// (docs/06-data-model.md, "Правила парсера", rule 3). It is counted while the
  /// body arrives, after `dart:io` has inflated it: a body is dropped the
  /// moment it passes the cap, not once it is already in memory.
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

  /// Deadline for one whole fetch.
  final Duration totalTimeout;

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
  ///
  /// [extraHeaders] go to the host of [url] and to no other. They are the
  /// device identity (ADR-0009), promised to the subscription's host only: a
  /// redirect to another host — a CDN, a mirror, where a short link points —
  /// is followed without them.
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

    final fetched = await _get(
      url,
      throughTunnel: throughTunnel,
      headers: <String, String>{
        HttpHeaders.userAgentHeader: userAgentOverride ?? userAgent,
        HttpHeaders.acceptHeader: '*/*',
      },
      hostOnlyHeaders: extraHeaders,
      cancelToken: cancelToken,
    );
    return fetched.map(
      (value) => HttpTextResponse(
        statusCode: value.statusCode,
        // What dio's own plain decoding did: a stray invalid byte in a
        // subscription is the parser's problem, not a failed fetch.
        body: utf8.decode(value.bytes, allowMalformed: true),
        headers: _normaliseHeaders(value.headers),
        url: value.url,
      ),
    );
  }

  /// Fetches [url] as bytes.
  ///
  /// The binary sibling of [fetchText], and it exists for exactly one caller:
  /// a `.srs` rule set is a compiled binary, and reading one as a string
  /// mangles it. Same cap, same schemes, same deadlines — a body over
  /// [maxBodyBytes] is refused rather than held.
  Future<Result<List<int>, CommyFailure>> fetchBytes(
    Uri url, {
    required bool throughTunnel,
    CancelToken? cancelToken,
  }) async {
    if (!allowedSchemes.contains(url.scheme.toLowerCase())) {
      return Err<List<int>, CommyFailure>(
        CommyFailure.subscriptionMalformed(
          'unsupported URL scheme: ${url.scheme}',
        ),
      );
    }

    final fetched = await _get(
      url,
      throughTunnel: throughTunnel,
      headers: <String, String>{
        HttpHeaders.userAgentHeader: userAgent,
        HttpHeaders.acceptHeader: '*/*',
      },
      cancelToken: cancelToken,
    );
    return fetched.flatMap((value) {
      if (value.bytes.isEmpty) {
        return Err<List<int>, CommyFailure>(
          CommyFailure.subscriptionMalformed('$url answered with no body'),
        );
      }
      return Ok<List<int>, CommyFailure>(value.bytes);
    });
  }

  /// Closes both underlying clients.
  void close({bool force = false}) {
    _direct?.close(force: force);
    _proxied?.close(force: force);
    _direct = null;
    _proxied = null;
  }

  /// One GET of [url], redirects and all, the body read under the cap,
  /// within [totalTimeout].
  ///
  /// Each hop gets a token of its own, so that the deadline and the cap can
  /// stop it without touching [cancelToken], which belongs to the caller — and
  /// a caller that cancels still stops it. [hostOnlyHeaders] are sent to the
  /// host of [url] only.
  Future<Result<_Fetched, CommyFailure>> _get(
    Uri url, {
    required bool throughTunnel,
    required Map<String, String> headers,
    Map<String, String> hostOnlyHeaders = const <String, String>{},
    CancelToken? cancelToken,
  }) {
    final hops = _HopTokens();
    if (cancelToken != null) {
      unawaited(cancelToken.whenCancel.then((_) => hops.abandon()));
    }
    return _follow(
      url,
      throughTunnel: throughTunnel,
      headers: headers,
      hostOnlyHeaders: hostOnlyHeaders,
      hops: hops,
    ).timeout(
      totalTimeout,
      onTimeout: () {
        hops.abandon();
        return Err<_Fetched, CommyFailure>(
          NetworkFailureMapper.deadline(url, totalTimeout),
        );
      },
    );
  }

  Future<Result<_Fetched, CommyFailure>> _follow(
    Uri url, {
    required bool throughTunnel,
    required Map<String, String> headers,
    required Map<String, String> hostOnlyHeaders,
    required _HopTokens hops,
  }) async {
    var target = url;
    for (var redirects = 0;; redirects++) {
      final fetched = await _read(
        target,
        origin: url,
        throughTunnel: throughTunnel,
        headers: <String, String>{
          ...headers,
          if (_sameHost(target, url)) ...hostOnlyHeaders,
        },
        token: hops.next(),
      );
      final location = fetched.valueOrNull?.location;
      if (location == null) {
        return fetched;
      }
      if (redirects >= maxRedirects) {
        return Err<_Fetched, CommyFailure>(
          NetworkFailureMapper.redirectRefused(
            url,
            'more than $maxRedirects redirects',
          ),
        );
      }
      final next = Uri.tryParse(location);
      final resolved = next == null ? null : target.resolveUri(next);
      final scheme = resolved?.scheme.toLowerCase() ?? '';
      if (resolved == null ||
          !allowedSchemes.contains(scheme) ||
          resolved.host.isEmpty) {
        return Err<_Fetched, CommyFailure>(
          NetworkFailureMapper.redirectRefused(
            url,
            'unusable Location${scheme.isEmpty ? '' : ' ($scheme)'}',
          ),
        );
      }
      // Once a fetch is encrypted it stays so. Past such a hop the request
      // path — a subscription token — and the answer — a list of
      // credentials — would cross the network in the clear, on the say-so of
      // one response header. A user who wants plain http can type it.
      if (target.scheme.toLowerCase() == 'https' && scheme == 'http') {
        return Err<_Fetched, CommyFailure>(
          NetworkFailureMapper.insecureRedirect(url),
        );
      }
      target = resolved;
    }
  }

  /// Whether [a] and [b] name the same host.
  ///
  /// Exactly the same: a subdomain is another host the user did not type,
  /// and a port is not a host.
  static bool _sameHost(Uri a, Uri b) =>
      a.host.toLowerCase() == b.host.toLowerCase();

  /// One request to [url], the body read under the cap unless it redirects.
  ///
  /// Failures name [origin], the address the caller asked for, whichever hop
  /// they happened on.
  Future<Result<_Fetched, CommyFailure>> _read(
    Uri url, {
    required Uri origin,
    required bool throughTunnel,
    required Map<String, String> headers,
    required CancelToken token,
  }) async {
    final client = throughTunnel ? _proxiedDio() : _directDio();
    try {
      final response = await client.getUri<ResponseBody>(
        url,
        options: Options(
          // A stream, not `plain` or `bytes`: those hand the body over only
          // once all of it is in memory, which is exactly what the cap is
          // there to prevent.
          responseType: ResponseType.stream,
          // Followed by [_follow], which decides what the next hop is sent.
          followRedirects: false,
          // Repeated per request, not just on the base options, so that an
          // injected `Dio` — a test double, or a future adapter — cannot end
          // up without a deadline and hang the refresh forever.
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          headers: headers,
          // 3xx comes back to [_follow]; anything at or above 400 is an error
          // we want to see as one.
          validateStatus: (status) => status != null && status < 400,
        ),
        cancelToken: token,
      );
      final status = response.statusCode ?? 0;
      if (redirectStatuses.contains(status)) {
        final location =
            response.headers[HttpHeaders.locationHeader]?.firstOrNull ?? '';
        if (location.trim().isEmpty) {
          return Err<_Fetched, CommyFailure>(
            NetworkFailureMapper.redirectRefused(origin, 'no Location'),
          );
        }
        // The body of a redirect is never read: the `finally` below stops it.
        return Ok<_Fetched, CommyFailure>(
          _Fetched(
            statusCode: status,
            bytes: Uint8List(0),
            headers: response.headers,
            url: url,
            location: location.trim(),
          ),
        );
      }
      final body = response.data;
      final bytes = body == null ? Uint8List(0) : await _capped(body, token);
      if (bytes == null) {
        return Err<_Fetched, CommyFailure>(
          NetworkFailureMapper.tooLarge(origin, maxBodyBytes),
        );
      }
      return Ok<_Fetched, CommyFailure>(
        _Fetched(
          statusCode: status,
          bytes: bytes,
          headers: response.headers,
          url: url,
        ),
      );
    } on DioException catch (error) {
      return Err<_Fetched, CommyFailure>(
        NetworkFailureMapper.fromDio(error, origin),
      );
    } on Object catch (error) {
      return Err<_Fetched, CommyFailure>(
        NetworkFailureMapper.fromError(error, origin),
      );
    } finally {
      // Whatever is still arriving — the body of an error status, which dio
      // keeps reading into a buffer nobody drains, or the rest of one over
      // the cap — stops here. A no-op on a body that was read to the end.
      token.cancel();
    }
  }

  /// The body of [body], or `null` the moment it passes [maxBodyBytes].
  ///
  /// A `Content-Length` over the cap is refused before a byte is read; one
  /// that lies, or is missing, is caught by the count.
  Future<Uint8List?> _capped(ResponseBody body, CancelToken token) async {
    final declared = int.tryParse(
      body.headers[HttpHeaders.contentLengthHeader]?.firstOrNull ?? '',
    );
    if (declared != null && declared > maxBodyBytes) {
      token.cancel();
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maxBodyBytes) {
        token.cancel();
        return null;
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
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
        // Every request follows its redirects by hand (see [_follow]); a
        // default of `true` here would only wait for a call that forgot.
        followRedirects: false,
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

/// What one fetch brought back, before it is read as text or kept as bytes.
class _Fetched {
  const _Fetched({
    required this.statusCode,
    required this.bytes,
    required this.headers,
    required this.url,
    this.location,
  });

  final int statusCode;
  final Uint8List bytes;
  final Headers headers;

  /// The address this came from, after the redirects before it.
  final Uri url;

  /// Where a redirect points, as the server wrote it; `null` for an answer.
  final String? location;
}

/// The token of the request in flight, across the hops of one fetch.
///
/// Each hop gets a fresh token, because the one before it was cancelled to
/// stop its body; giving up — the deadline, or the caller's own token — has
/// to reach whichever hop is running at the time.
class _HopTokens {
  CancelToken _current = CancelToken();
  bool _abandoned = false;

  CancelToken next() {
    _current = CancelToken();
    if (_abandoned) {
      _current.cancel();
    }
    return _current;
  }

  void abandon() {
    _abandoned = true;
    _current.cancel();
  }
}
