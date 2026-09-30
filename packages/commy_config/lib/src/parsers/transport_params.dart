import 'package:commy_config/src/builder/xhttp_download_builder.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/query_map.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:commy_domain/commy_domain.dart';

/// The transport and TLS half of a link, shared by VLESS, VMess and Trojan.
///
/// These three protocols spell the same ten options in about thirty different
/// ways depending on which panel generated the link. Absorbing that here
/// keeps the protocol parsers about the protocol.
abstract final class TransportParams {
  /// Every transport spelling seen in the wild, mapped to ours.
  static const Map<String, String> transportAliases = <String, String>{
    'tcp': 'tcp',
    'raw': 'tcp',
    'none': 'tcp',
    'original': 'tcp',
    'ws': 'ws',
    'websocket': 'ws',
    'grpc': 'grpc',
    'gun': 'grpc',
    'http': 'http',
    'h2': 'http',
    'h2c': 'http',
    'httpupgrade': 'httpupgrade',
    'quic': 'quic',
    'xhttp': 'xhttp',
    'splithttp': 'xhttp',
  };

  /// Transports the core can actually carry.
  ///
  /// `ws`, `grpc`, `http`, `httpupgrade` and `quic` are sing-box's own, read
  /// off `option.V2RayTransportOptions` at tag v1.13.16. `xhttp` is Xray's
  /// transport and sing-box does not have it: ours does, because the build
  /// adds it (core/xhttp, docs/adr/0010-xhttp-transport.md). Anything outside
  /// this set is refused at import time, by name, instead of letting the tunnel
  /// fail at connect time.
  static const Set<String> supported = <String>{
    'tcp',
    'ws',
    'grpc',
    'http',
    'httpupgrade',
    'quic',
    xhttp,
  };

  /// The name XHTTP is stored under. `splithttp`, its first name, maps to it.
  static const String xhttp = 'xhttp';

  /// Query keys that may hold the transport name.
  static const List<String> transportKeys = <String>[
    'type',
    'net',
    'network',
  ];

  /// Query keys that may hold the TLS server name.
  static const List<String> sniKeys = <String>[
    'sni',
    'peer',
    'servername',
    'serversname',
  ];

  /// Query keys that may hold the uTLS fingerprint.
  static const List<String> fingerprintKeys = <String>[
    'fp',
    'fingerprint',
    'client-fingerprint',
    'clientfingerprint',
  ];

  /// Query keys that may hold the Reality public key.
  static const List<String> publicKeyKeys = <String>[
    'pbk',
    'publickey',
    'public-key',
  ];

  /// Query keys that may hold the Reality short id.
  static const List<String> shortIdKeys = <String>[
    'sid',
    'shortid',
    'short-id',
  ];

  /// Query keys that may hold the Reality spider URL.
  static const List<String> spiderKeys = <String>[
    'spx',
    'spiderx',
    'spider-x',
  ];

  /// Query keys that switch certificate verification off.
  static const List<String> insecureKeys = <String>[
    'allowinsecure',
    'allow_insecure',
    'insecure',
    'skip-cert-verify',
    'skipcertverify',
  ];

  /// Query keys that may hold the gRPC service name.
  static const List<String> serviceNameKeys = <String>[
    'servicename',
    'service_name',
    'grpc-service-name',
  ];

  /// Query keys that may hold the TCP header obfuscation type.
  static const List<String> headerTypeKeys = <String>[
    'headertype',
    'header_type',
  ];

  /// Query keys that may hold the TLS security mode.
  static const List<String> securityKeys = <String>['security', 'tls'];

  /// The TCP header type that opens the connection with a fake HTTP request.
  static const String httpHeader = 'http';

  /// Whether [headerType] asks for Xray's HTTP header on plain TCP.
  static bool isHttpHeader(String? headerType) =>
      headerType?.trim().toLowerCase() == httpHeader;

  /// Why the core cannot carry plain TCP with [headerType] under [security],
  /// or `null` when it can.
  ///
  /// Xray's TCP has two headers: none, and `http`, which opens the connection
  /// with a fake HTTP/1.1 request. sing-box sends exactly that through its
  /// `http` transport, but only without TLS: with TLS the same transport
  /// speaks HTTP/2, which such an inbound does not accept. Checked at import,
  /// so the node is refused by name instead of connecting as bare TCP and
  /// failing every time, and again when the config is built, for nodes
  /// stored before the rule existed.
  static String? tcpHeaderRefusal(String? headerType, String? security) {
    final header = headerType?.trim().toLowerCase();
    if (header == null || header.isEmpty || header == 'none') {
      return null;
    }
    if (header != httpHeader) {
      return 'TCP header "$headerType" is not carried by the core';
    }
    final mode = security?.trim().toLowerCase();
    if (mode == ParamKeys.securityTls || mode == ParamKeys.securityReality) {
      return 'TCP with an HTTP header cannot run over TLS or REALITY in the '
          'core';
    }
    return null;
  }

  /// Throws [LinkFormatException] when [params] hold a plain TCP node the
  /// core cannot carry (see [tcpHeaderRefusal]).
  static void checkTcpHeader(Map<String, Object?> params) {
    if (params[ParamKeys.transport] != 'tcp') {
      return;
    }
    final refusal = tcpHeaderRefusal(
      params[ParamKeys.headerType] as String?,
      params[ParamKeys.security] as String?,
    );
    if (refusal != null) {
      throw LinkFormatException(refusal);
    }
  }

  /// Maps a transport spelling onto ours, or returns `null` when unknown.
  ///
  /// An empty or missing value means `tcp`, which is what every panel means
  /// when it leaves the field out.
  static String? normaliseTransport(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return 'tcp';
    }
    return transportAliases[value];
  }

  /// Maps a TLS spelling onto `none`, `tls` or `reality`.
  ///
  /// Returns `null` when the value means nothing to us, so the caller can
  /// fall back to the protocol's own default.
  static String? normaliseSecurity(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value == 'reality') {
      return ParamKeys.securityReality;
    }
    if (value == 'tls' || value == 'xtls' || QueryMap.truthy.contains(value)) {
      return ParamKeys.securityTls;
    }
    if (value == 'none' || value == '0' || value == 'false') {
      return ParamKeys.securityNone;
    }
    return null;
  }

  /// Reads every transport and TLS field of [query] into [params].
  ///
  /// [uriPath] is the path part of the link, which a few panels use instead
  /// of `?path=`. [defaultSecurity] is what the protocol implies when the
  /// link says nothing — `none` for VLESS, `tls` for Trojan.
  static void readInto(
    Map<String, Object?> params,
    QueryMap query, {
    required String defaultSecurity,
    String uriPath = '',
  }) {
    final rawTransport = query.firstOf(transportKeys);
    final transport = normaliseTransport(rawTransport);
    if (transport == null || !supported.contains(transport)) {
      throw LinkFormatException(
        'Transport "$rawTransport" is not supported by the core',
      );
    }
    params[ParamKeys.transport] = transport;

    final reality = query.firstOf(publicKeyKeys);
    final declared = normaliseSecurity(query.firstOf(securityKeys));
    params[ParamKeys.security] = reality != null
        ? ParamKeys.securityReality
        : declared ?? defaultSecurity;

    final alpn = query.csvOf(<String>['alpn']);
    final rawPath = query.first('path') ??
        (uriPath.isEmpty || uriPath == '/' ? null : Percent.decode(uriPath));
    final serviceName = query.firstOf(serviceNameKeys) ??
        (transport == 'grpc' ? rawPath : null);

    params[ParamKeys.sni] = query.firstOf(sniKeys);
    params[ParamKeys.alpn] = alpn.isEmpty ? null : alpn.join(',');
    params[ParamKeys.fingerprint] = query.firstOf(fingerprintKeys);
    params[ParamKeys.publicKey] = reality;
    params[ParamKeys.shortId] = query.firstOf(shortIdKeys);
    params[ParamKeys.spiderX] = query.firstOf(spiderKeys);
    params[ParamKeys.flow] = query.first('flow');
    params[ParamKeys.path] = transport == 'grpc' ? null : rawPath;
    params[ParamKeys.host] = query.first('host');
    params[ParamKeys.serviceName] = serviceName;
    params[ParamKeys.headerType] = query.firstOf(headerTypeKeys);
    checkTcpHeader(params);
    params[ParamKeys.mode] = query.first('mode');
    if (transport == xhttp) {
      readXhttpInto(
        params,
        mode: query.first('mode'),
        extra: query.first('extra'),
      );
    }
    if (query.firstOf(insecureKeys) != null) {
      params[ParamKeys.allowInsecure] =
          query.flagOf(insecureKeys, orElse: false);
    }
    if (query.first('disablesni') != null) {
      params[ParamKeys.disableSni] = query.flag('disablesni', orElse: false);
    }
  }

  /// Checks and stores what only an XHTTP node has: its [mode] and [extra].
  ///
  /// [extra] is the JSON object of a share link's `extra=`, as text. Text that
  /// is not a JSON object is dropped rather than refused — the node still has
  /// its host and path, and the defaults are what most servers run with. An
  /// object Xray itself would refuse is refused, by the rule it breaks.
  static void readXhttpInto(
    Map<String, Object?> params, {
    required String? mode,
    required String? extra,
  }) {
    final normalisedMode = mode?.trim().toLowerCase();
    final effectiveMode = normalisedMode == null || normalisedMode.isEmpty
        ? XhttpSettings.modeAuto
        : normalisedMode;
    if (!XhttpSettings.modes.contains(effectiveMode)) {
      throw LinkFormatException('XHTTP mode "$mode" does not exist');
    }
    params[ParamKeys.mode] = normalisedMode;

    final settings = XhttpSettings.tryParseExtra(extra);
    if (settings == null || settings.isEmpty) {
      params[ParamKeys.extra] = null;
    } else {
      try {
        settings.validate(effectiveMode);
        // A second route that could never be built is refused now, with the
        // entry, rather than at every connect. The port only stands in for a
        // route that names none; any will do for the check.
        XhttpDownloadBuilder.build(
          settings.downloadSettings,
          mainPort: 443,
          mainMode: effectiveMode,
        );
      } on ConfigBuildException catch (error) {
        throw LinkFormatException(error.reason);
      }
      params[ParamKeys.extra] = extra!.trim();
    }
    final host = params[ParamKeys.host];
    if ((host == null || '$host'.isEmpty) && settings?.hostHeader != null) {
      params[ParamKeys.host] = settings!.hostHeader;
    }
  }

  /// Order the transport keys are written back in, so exports are stable.
  static const List<String> exportOrder = <String>[
    ParamKeys.transport,
    ParamKeys.security,
    ParamKeys.encryption,
    ParamKeys.flow,
    ParamKeys.sni,
    ParamKeys.fingerprint,
    ParamKeys.alpn,
    ParamKeys.publicKey,
    ParamKeys.shortId,
    ParamKeys.spiderX,
    ParamKeys.path,
    ParamKeys.host,
    ParamKeys.serviceName,
    ParamKeys.headerType,
    ParamKeys.mode,
    ParamKeys.extra,
    ParamKeys.allowInsecure,
  ];

  /// Renders the transport half of [node] back into query entries.
  static List<MapEntry<String, String>> writeQuery(ProxyNode node) {
    final entries = <MapEntry<String, String>>[];
    for (final key in exportOrder) {
      final value = node.param(key);
      if (value == null || value.isEmpty) {
        continue;
      }
      if (value == 'false') {
        continue;
      }
      entries.add(
        MapEntry<String, String>(key, value == 'true' ? '1' : value),
      );
    }
    return entries;
  }

  /// Joins query entries into a query string, without the leading `?`.
  static String buildQuery(List<MapEntry<String, String>> entries) {
    return entries
        .map(
          (entry) => '${entry.key}=${Percent.encodeQueryValue(entry.value)}',
        )
        .join('&');
  }
}
