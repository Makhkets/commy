import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/xhttp_download_builder.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `transport` block of a VLESS, VMess or Trojan outbound.
///
/// Mirrors `option.V2RayTransportOptions` at tag v1.13.16, plus the one
/// transport our build of the core adds: `xhttp`, whose block is
/// `config.Options` in `core/xhttp/config`. The field list per transport is
/// closed — the core decodes with `DisallowUnknownFields`, so a field borrowed
/// from another transport is a startup error rather than a setting that
/// quietly does nothing.
abstract final class TransportOptionsBuilder {
  /// Transports that need no block at all.
  static const String plainTransport = 'tcp';

  /// Header the WebSocket early-data payload rides in.
  ///
  /// Xray and v2rayN encode early data as `?ed=2048` on the path and imply
  /// this header; sing-box wants both spelled out.
  static const String earlyDataHeader = 'Sec-WebSocket-Protocol';

  /// The `Host` header key, spelled the way an HTTP header is spelled.
  static const String hostHeader = 'Host';

  /// Builds the block for [node], or returns `null` for bare TCP.
  static Map<String, Object?>? build(ProxyNode node) {
    final transport = node.param(ParamKeys.transport) ?? plainTransport;
    switch (transport) {
      case plainTransport:
        return _tcp(node);
      case 'ws':
        return _websocket(node);
      case 'grpc':
        return _grpc(node);
      case 'http':
        return _http(node);
      case 'httpupgrade':
        return _httpUpgrade(node);
      case 'quic':
        return <String, Object?>{SingBoxKeys.type: 'quic'};
      case TransportParams.xhttp:
        return _xhttp(node);
      default:
        throw ConfigBuildException(
          'Transport "$transport" is not carried by the sing-box core',
        );
    }
  }

  /// Splits `/path?ed=2048` into the path and the early-data window.
  ///
  /// Returns the path unchanged and a `null` window when there is no `ed`.
  static EarlyData splitEarlyData(String rawPath) {
    final question = rawPath.indexOf('?');
    if (question < 0) {
      return EarlyData(rawPath, null);
    }
    final path = rawPath.substring(0, question);
    for (final pair in rawPath.substring(question + 1).split('&')) {
      final split = pair.indexOf('=');
      if (split <= 0) {
        continue;
      }
      if (pair.substring(0, split).trim().toLowerCase() != 'ed') {
        continue;
      }
      final size = int.tryParse(pair.substring(split + 1).trim());
      if (size != null && size > 0) {
        return EarlyData(path.isEmpty ? '/' : path, size);
      }
    }
    return EarlyData(path.isEmpty ? '/' : path, null);
  }

  /// Bare TCP, or TCP opened with Xray's fake HTTP/1.1 request.
  ///
  /// The request is what sing-box's `http` transport sends when there is no
  /// TLS (see TransportParams.tcpHeaderRefusal for why TLS is refused). The
  /// method is spelled out because the two disagree on the default: Xray's
  /// header sends GET, sing-box's transport PUT.
  static Map<String, Object?>? _tcp(ProxyNode node) {
    final headerType = node.param(ParamKeys.headerType);
    final refusal = TransportParams.tcpHeaderRefusal(
      headerType,
      node.param(ParamKeys.security),
    );
    if (refusal != null) {
      throw ConfigBuildException(refusal);
    }
    if (!TransportParams.isHttpHeader(headerType)) {
      return null;
    }
    List<String> split(String? raw) => <String>[
          for (final part in (raw ?? '').split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ];
    final options = <String, Object?>{SingBoxKeys.type: 'http'};
    final hosts = split(node.param(ParamKeys.host));
    if (hosts.isNotEmpty) {
      options[SingBoxKeys.host] = hosts;
    }
    // The header may list several paths; a share link joins them with commas
    // and Xray picks one per request. The first serves as well as any.
    final paths = split(node.param(ParamKeys.path));
    options[SingBoxKeys.path] = paths.isEmpty ? '/' : paths.first;
    options[SingBoxKeys.httpMethod] = 'GET';
    return options;
  }

  static Map<String, Object?> _websocket(ProxyNode node) {
    final options = <String, Object?>{SingBoxKeys.type: 'ws'};
    final rawPath = node.param(ParamKeys.path);
    if (rawPath != null && rawPath.isNotEmpty) {
      final split = splitEarlyData(rawPath);
      options[SingBoxKeys.path] = split.path;
      final window = split.maxEarlyData;
      if (window != null) {
        options['max_early_data'] = window;
        options['early_data_header_name'] = earlyDataHeader;
      }
    }
    final host = node.param(ParamKeys.host);
    if (host != null && host.isNotEmpty) {
      options[SingBoxKeys.headers] = <String, Object?>{hostHeader: host};
    }
    return options;
  }

  static Map<String, Object?> _grpc(ProxyNode node) {
    final serviceName =
        node.param(ParamKeys.serviceName) ?? node.param(ParamKeys.path);
    final options = <String, Object?>{SingBoxKeys.type: 'grpc'};
    if (serviceName != null && serviceName.isNotEmpty) {
      options[SingBoxKeys.serviceName] = _stripSlashes(serviceName);
    }
    return options;
  }

  static Map<String, Object?> _http(ProxyNode node) {
    final options = <String, Object?>{SingBoxKeys.type: 'http'};
    final host = node.param(ParamKeys.host);
    if (host != null && host.isNotEmpty) {
      options[SingBoxKeys.host] = <String>[
        for (final part in host.split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    final path = node.param(ParamKeys.path);
    if (path != null && path.isNotEmpty) {
      options[SingBoxKeys.path] = splitEarlyData(path).path;
    }
    final method = node.param(ParamKeys.headerType);
    if (method != null && _isHttpMethod(method)) {
      options[SingBoxKeys.httpMethod] = method.toUpperCase();
    }
    return options;
  }

  static Map<String, Object?> _httpUpgrade(ProxyNode node) {
    final options = <String, Object?>{SingBoxKeys.type: 'httpupgrade'};
    final host = node.param(ParamKeys.host);
    if (host != null && host.isNotEmpty) {
      // A plain string here, unlike `http`, which takes a list.
      options[SingBoxKeys.host] = host.split(',').first.trim();
    }
    final path = node.param(ParamKeys.path);
    if (path != null && path.isNotEmpty) {
      options[SingBoxKeys.path] = splitEarlyData(path).path;
    }
    return options;
  }

  /// The XHTTP mode [node] runs in: what the link said, or `auto`.
  static String xhttpMode(ProxyNode node) {
    final mode = node.param(ParamKeys.mode)?.trim().toLowerCase();
    return mode == null || mode.isEmpty ? XhttpSettings.modeAuto : mode;
  }

  static Map<String, Object?> _xhttp(ProxyNode node) {
    final mode = xhttpMode(node);
    final settings = _xhttpSettings(node, mode);

    final options = <String, Object?>{SingBoxKeys.type: TransportParams.xhttp};
    if (mode != XhttpSettings.modeAuto) {
      options['mode'] = mode;
    }
    options.addAll(_xhttpRoute(node, settings));
    final download = XhttpDownloadBuilder.build(
      settings.downloadSettings,
      mainPort: node.port,
      mainMode: mode,
    );
    if (download != null) {
      options[SingBoxKeys.download] = download;
    }
    return options;
  }

  /// The host, path and settings of the XHTTP route [node] describes,
  /// without its type and mode: the part of the block a second route has
  /// too. With [download], only what that route's GET is dressed by (see
  /// XhttpSettings.toCore).
  static Map<String, Object?> xhttpRoute(
    ProxyNode node, {
    bool download = false,
  }) =>
      _xhttpRoute(
        node,
        _xhttpSettings(node, xhttpMode(node)),
        download: download,
      );

  /// The settings of [node], held to the rules of [mode].
  static XhttpSettings _xhttpSettings(ProxyNode node, String mode) {
    // Checked again here, not only at import: the node may come from a
    // database written before a rule existed, and what the core refuses it
    // refuses for the whole document, not for one server.
    return (XhttpSettings.tryParseExtra(node.param(ParamKeys.extra)) ??
        XhttpSettings.read(const <String, Object?>{}))
      ..validate(mode);
  }

  static Map<String, Object?> _xhttpRoute(
    ProxyNode node,
    XhttpSettings settings, {
    bool download = false,
  }) {
    final options = <String, Object?>{};
    final host = node.param(ParamKeys.host) ?? settings.hostHeader;
    if (host != null && host.isNotEmpty) {
      // One name, unlike `http`: it becomes the Host header as it stands.
      options[SingBoxKeys.host] = host.split(',').first.trim();
    }
    final path = node.param(ParamKeys.path);
    if (path != null && path.isNotEmpty) {
      // Left whole. An XHTTP path may carry a query string of its own, and it
      // is sent to the server as written — `?ed=` means nothing here.
      options[SingBoxKeys.path] = path;
    }
    return options..addAll(settings.toCore(download: download));
  }

  static bool _isHttpMethod(String value) => const <String>{
        'get',
        'post',
        'put',
        'patch',
        'delete',
        'head',
        'options',
      }.contains(value.toLowerCase());

  static String _stripSlashes(String value) {
    var result = value;
    while (result.startsWith('/')) {
      result = result.substring(1);
    }
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

/// A websocket path split into its route and its early-data window.
///
/// Public because [TransportOptionsBuilder.splitEarlyData] returns it, and a
/// private return type on a public method is unusable from outside.
class EarlyData {
  /// Wraps a [path] and the `ed` window it carried, if any.
  const EarlyData(this.path, this.maxEarlyData);

  /// The route, with the query string removed.
  final String path;

  /// The `ed` value in bytes, or `null` when the link had none.
  final int? maxEarlyData;
}
