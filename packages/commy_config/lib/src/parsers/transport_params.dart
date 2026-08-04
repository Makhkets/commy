import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/query_map.dart';
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

  /// Transports the sing-box core can actually carry.
  ///
  /// Read off `option.V2RayTransportOptions` at tag v1.13.16: the core has
  /// `ws`, `grpc`, `http`, `httpupgrade` and `quic`, and nothing else. `xhttp`
  /// is an Xray transport and stays out on purpose — recognising it in
  /// [transportAliases] only so the import failure can name it, and rejecting
  /// it here, tells the user at import time instead of letting the tunnel fail
  /// silently at connect time.
  static const Set<String> supported = <String>{
    'tcp',
    'ws',
    'grpc',
    'http',
    'httpupgrade',
    'quic',
  };

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
    params[ParamKeys.mode] = query.first('mode');
    if (query.firstOf(insecureKeys) != null) {
      params[ParamKeys.allowInsecure] =
          query.flagOf(insecureKeys, orElse: false);
    }
    if (query.first('disablesni') != null) {
      params[ParamKeys.disableSni] = query.flag('disablesni', orElse: false);
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
