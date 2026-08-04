import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `transport` block of a VLESS, VMess or Trojan outbound.
///
/// Mirrors `option.V2RayTransportOptions` at tag v1.13.16. The field list per
/// transport is closed — the core decodes with `DisallowUnknownFields`, so a
/// field borrowed from another transport is a startup error rather than a
/// setting that quietly does nothing.
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

  /// Builds the block for [node], or returns `null` for plain TCP.
  static Map<String, Object?>? build(ProxyNode node) {
    final transport = node.param(ParamKeys.transport) ?? plainTransport;
    switch (transport) {
      case plainTransport:
        return null;
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
