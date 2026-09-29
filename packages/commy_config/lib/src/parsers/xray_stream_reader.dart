import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/xhttp_download_settings.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:commy_config/src/parsers/transport_params.dart';

/// Reads an Xray `streamSettings` object into node parameters.
///
/// Two places hand one over: an outbound of an Xray JSON subscription, and
/// the `downloadSettings` of an XHTTP transport, which Xray parses with the
/// very same `StreamConfig` (infra/conf/transport_internet.go) — so both are
/// read here, by one reader, and mean the same thing.
abstract final class XrayStreamReader {
  /// Xray `network` values mapped onto our transport names.
  static const Map<String, String> networks = <String, String>{
    'tcp': 'tcp',
    'raw': 'tcp',
    'ws': 'ws',
    'websocket': 'ws',
    'grpc': 'grpc',
    'gun': 'grpc',
    'h2': 'http',
    'http': 'http',
    'httpupgrade': 'httpupgrade',
    'quic': 'quic',
    'xhttp': TransportParams.xhttp,
    'splithttp': TransportParams.xhttp,
  };

  /// `security` values Xray accepts, spelled as it spells them.
  static const Set<String> _knownSecurity = <String>{
    '',
    'none',
    'tls',
    'xtls',
    'reality',
  };

  /// Reads [stream] into [params].
  ///
  /// [downloadRoute] is for a `downloadSettings`. Two things differ there. A
  /// `security` Xray does not know is refused, where an outbound has always
  /// had it read as none: a second route that quietly loses its TLS is worse
  /// than a node left out. And a `downloadSettings` of its own is dropped,
  /// as Xray's dialer drops it: only the main route's is ever read.
  ///
  /// Throws [LinkFormatException] when the transport is one the core does not
  /// carry, or the XHTTP settings break a rule Xray checks.
  static void readInto(
    Map<String, Object?> params,
    Map<String, Object?> stream, {
    bool downloadRoute = false,
  }) {
    // `method` is v26.9.9's second name for `network`, and wins over it
    // when both are there (`if c.Method != nil { c.Network = c.Method }`).
    final rawNetwork =
        MapRead.text(stream, <String>['method', 'network']) ?? 'tcp';
    final transport = networks[rawNetwork.toLowerCase()];
    if (transport == null || !TransportParams.supported.contains(transport)) {
      throw LinkFormatException(
        'Transport "$rawNetwork" is not supported by the core',
      );
    }
    params[ParamKeys.transport] = transport;

    final reality = MapRead.object(stream, <String>['realitySettings']);
    final tls = MapRead.object(stream, <String>['tlsSettings']);
    final security =
        MapRead.text(stream, <String>['security'])?.toLowerCase() ?? '';
    if (downloadRoute && !_knownSecurity.contains(security)) {
      throw LinkFormatException('Security "$security" does not exist');
    }
    // Xray decides by `security` alone; a `realitySettings` left over from a
    // copied config means nothing next to `"security": "tls"`. Only an
    // outbound that names no security at all is read by what it carries, as
    // it always has been here.
    final isReality = security == 'reality' ||
        (!downloadRoute && security.isEmpty && reality != null);
    if (isReality) {
      params[ParamKeys.security] = ParamKeys.securityReality;
      // `password` is the name Xray gave the public key after v26.3.27.
      params[ParamKeys.publicKey] = reality == null
          ? null
          : MapRead.text(reality, <String>['publicKey', 'password']);
      params[ParamKeys.shortId] =
          reality == null ? null : MapRead.text(reality, <String>['shortId']);
      params[ParamKeys.spiderX] =
          reality == null ? null : MapRead.text(reality, <String>['spiderX']);
      params[ParamKeys.sni] = reality == null
          ? null
          : MapRead.text(reality, <String>['serverName']);
      params[ParamKeys.fingerprint] = reality == null
          ? null
          : MapRead.text(reality, <String>['fingerprint']);
    } else if (security == 'tls' || security == 'xtls') {
      params[ParamKeys.security] = ParamKeys.securityTls;
      params[ParamKeys.sni] =
          tls == null ? null : MapRead.text(tls, <String>['serverName']);
      params[ParamKeys.fingerprint] =
          tls == null ? null : MapRead.text(tls, <String>['fingerprint']);
      params[ParamKeys.alpn] = tls == null ? null : _alpn(tls);
      params[ParamKeys.allowInsecure] = tls != null &&
          (MapRead.boolean(tls, <String>['allowInsecure']) ?? false);
      // Not Xray's: what XhttpDownloadSettings keeps of a sing-box route.
      params[ParamKeys.disableSni] = tls != null &&
          (MapRead.boolean(
                tls,
                const <String>[XhttpDownloadSettings.disableSniKey],
              ) ??
              false);
    } else {
      params[ParamKeys.security] = ParamKeys.securityNone;
    }

    switch (transport) {
      case 'tcp':
        // `rawSettings` is the name since Xray renamed TCP to RAW.
        final options =
            MapRead.object(stream, <String>['tcpSettings', 'rawSettings']);
        final header = options == null
            ? null
            : MapRead.object(options, <String>['header']);
        final type =
            header == null ? null : MapRead.text(header, <String>['type']);
        params[ParamKeys.headerType] =
            type == null || type.toLowerCase() == 'none' ? null : type;
        final request =
            header == null ? null : MapRead.object(header, <String>['request']);
        if (request != null) {
          params[ParamKeys.path] =
              _joinOrNull(MapRead.stringList(request, <String>['path']));
          final headers = MapRead.object(request, <String>['headers']);
          params[ParamKeys.host] = headers == null
              ? null
              : _joinOrNull(MapRead.stringList(headers, <String>['host']));
        }
        TransportParams.checkTcpHeader(params);
      case 'ws':
        final options = MapRead.object(stream, <String>['wsSettings']);
        if (options != null) {
          params[ParamKeys.path] = MapRead.text(options, <String>['path']);
          final headers = MapRead.object(options, <String>['headers']);
          params[ParamKeys.host] = MapRead.text(options, <String>['host']) ??
              (headers == null
                  ? null
                  : MapRead.text(headers, <String>['host']));
        }
      case 'grpc':
        final options = MapRead.object(stream, <String>['grpcSettings']);
        if (options != null) {
          params[ParamKeys.serviceName] =
              MapRead.text(options, <String>['serviceName']);
        }
      case 'http':
        final options = MapRead.object(stream, <String>['httpSettings']);
        if (options != null) {
          params[ParamKeys.path] = MapRead.text(options, <String>['path']);
          params[ParamKeys.host] =
              _joinOrNull(MapRead.stringList(options, <String>['host']));
        }
      case 'httpupgrade':
        final options = MapRead.object(stream, <String>['httpupgradeSettings']);
        if (options != null) {
          params[ParamKeys.path] = MapRead.text(options, <String>['path']);
          params[ParamKeys.host] = MapRead.text(options, <String>['host']);
        }
      case TransportParams.xhttp:
        final options = MapRead.object(
              stream,
              <String>['xhttpSettings', 'splithttpSettings'],
            ) ??
            const <String, Object?>{};
        params[ParamKeys.path] = MapRead.text(options, <String>['path']);
        // Xray lets the settings sit beside host and path or inside `extra`,
        // and when `extra` is there it replaces the rest wholesale.
        final extra = MapRead.object(options, <String>['extra']);
        var settings = XhttpSettings.read(extra ?? options);
        if (downloadRoute) {
          settings = settings.withDownloadSettings(null);
        }
        // A Host among the headers is the host (see XhttpSettings.hostHeader).
        // It is taken here, from the settings as read: the text handed on
        // below no longer has it.
        params[ParamKeys.host] =
            MapRead.text(options, <String>['host']) ?? settings.hostHeader;
        TransportParams.readXhttpInto(
          params,
          mode: MapRead.text(options, <String>['mode']),
          extra: settings.toExtraJson(),
        );
    }
  }

  /// Xray takes `alpn` as a list or as one comma-separated string.
  static String? _alpn(Map<String, Object?> tls) {
    final list = MapRead.stringList(tls, <String>['alpn']);
    return _joinOrNull(<String>[
      for (final entry in list)
        for (final part in entry.split(','))
          if (part.trim().isNotEmpty) part.trim(),
    ]);
  }

  static String? _joinOrNull(List<String> values) =>
      values.isEmpty ? null : values.join(',');
}
