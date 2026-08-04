import 'dart:convert';

import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `vmess://` links in both formats that exist.
///
/// The old one, from v2rayN, is a base64 blob holding a JSON object with
/// abbreviated keys: `v`, `ps`, `add`, `port`, `id`, `aid`, `scy`, `net`,
/// `type`, `host`, `path`, `tls`, `sni`, `alpn`, `fp`. The newer one looks
/// like every other link: `vmess://uuid@host:port?...`.
///
/// Both are accepted. Exports use the base64 form, because that is the one
/// every other client can still read.
class VmessLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const VmessLinkParser();

  /// Key order used when exporting the base64 JSON form.
  static const List<String> exportKeyOrder = <String>[
    'v',
    'ps',
    'add',
    'port',
    'id',
    'aid',
    'scy',
    'net',
    'type',
    'host',
    'path',
    'tls',
    'sni',
    'alpn',
    'fp',
    'pbk',
    'sid',
    'spx',
    'flow',
  ];

  @override
  Set<String> get schemes => const <String>{'vmess'};

  @override
  Protocol get protocol => Protocol.vmess;

  @override
  ProxyNode parse(String raw) {
    final trimmed = raw.trim();
    final separator = trimmed.indexOf('://');
    if (separator <= 0 ||
        trimmed.substring(0, separator).toLowerCase() != 'vmess') {
      throw const LinkFormatException('Not a vmess:// link');
    }
    var payload = trimmed.substring(separator + 3);
    var fallbackName = '';
    final hash = payload.indexOf('#');
    if (hash >= 0) {
      fallbackName = Percent.decode(payload.substring(hash + 1)).trim();
      payload = payload.substring(0, hash);
    }
    final decoded = LenientBase64.decodeToString(payload);
    if (decoded != null && decoded.trimLeft().startsWith('{')) {
      return _parseLegacy(decoded, fallbackName);
    }
    return _parseModern(trimmed);
  }

  @override
  String toLink(ProxyNode node) {
    final uuid = node.param(ParamKeys.uuid);
    if (uuid == null || uuid.isEmpty) {
      throw const LinkFormatException('Node carries no user id');
    }
    final transport = node.param(ParamKeys.transport) ?? 'tcp';
    final security = node.param(ParamKeys.security) ?? ParamKeys.securityNone;
    final serviceName = node.param(ParamKeys.serviceName);
    final values = <String, String?>{
      'v': '2',
      'ps': node.name,
      'add': node.host,
      'port': '${node.port}',
      'id': uuid,
      'aid': node.param(ParamKeys.alterId) ?? '0',
      'scy': node.param(ParamKeys.vmessSecurity) ?? 'auto',
      'net': transport == 'http' ? 'h2' : transport,
      'type': node.param(ParamKeys.headerType) ?? 'none',
      'host': node.param(ParamKeys.host),
      'path': transport == 'grpc' ? serviceName : node.param(ParamKeys.path),
      'tls': security == ParamKeys.securityNone ? '' : security,
      'sni': node.param(ParamKeys.sni),
      'alpn': node.param(ParamKeys.alpn),
      'fp': node.param(ParamKeys.fingerprint),
      'pbk': node.param(ParamKeys.publicKey),
      'sid': node.param(ParamKeys.shortId),
      'spx': node.param(ParamKeys.spiderX),
      'flow': node.param(ParamKeys.flow),
    };
    final document = <String, Object?>{
      for (final key in exportKeyOrder)
        if (values[key] != null) key: values[key],
    };
    return 'vmess://${LenientBase64.encode(jsonEncode(document))}';
  }

  ProxyNode _parseLegacy(String json, String fallbackName) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const LinkFormatException('vmess:// payload is not valid JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const LinkFormatException('vmess:// payload is not a JSON object');
    }
    final host = _text(decoded['add']);
    if (host == null || !HostPort.isPlausibleHost(host.toLowerCase())) {
      throw const LinkFormatException('vmess:// payload has no server address');
    }
    final port = HostPort.parsePort(_text(decoded['port']) ?? '');
    if (port == null) {
      throw const LinkFormatException('vmess:// payload has no valid port');
    }
    final uuid = _text(decoded['id']);
    if (uuid == null) {
      throw const LinkFormatException('vmess:// payload has no user id');
    }
    final rawTransport = _text(decoded['net']);
    final transport = TransportParams.normaliseTransport(rawTransport);
    if (transport == null || !TransportParams.supported.contains(transport)) {
      throw LinkFormatException(
        'Transport "$rawTransport" is not supported by the core',
      );
    }
    final reality = _text(decoded['pbk']);
    final security = reality != null
        ? ParamKeys.securityReality
        : TransportParams.normaliseSecurity(_text(decoded['tls'])) ??
            ParamKeys.securityNone;
    final headerType = _text(decoded['type']);
    final path = _text(decoded['path']);
    final params = <String, Object?>{
      ParamKeys.uuid: uuid,
      ParamKeys.alterId: _text(decoded['aid']) ?? '0',
      ParamKeys.vmessSecurity: _text(decoded['scy']) ?? 'auto',
      ParamKeys.transport: transport,
      ParamKeys.security: security,
      ParamKeys.headerType: headerType == 'none' ? null : headerType,
      ParamKeys.host: _text(decoded['host']),
      ParamKeys.path: transport == 'grpc' ? null : path,
      ParamKeys.serviceName: transport == 'grpc' ? path : null,
      ParamKeys.sni: _text(decoded['sni']),
      ParamKeys.alpn: _text(decoded['alpn']),
      ParamKeys.fingerprint: _text(decoded['fp']),
      ParamKeys.publicKey: reality,
      ParamKeys.shortId: _text(decoded['sid']),
      ParamKeys.spiderX: _text(decoded['spx']),
      ParamKeys.flow: _text(decoded['flow']),
      ParamKeys.mode: _text(decoded['mode']),
    };
    final name = _text(decoded['ps']) ?? _text(decoded['remark']);
    return NodeFactory.build(
      protocol: Protocol.vmess,
      name: name ?? (fallbackName.isEmpty ? '$host:$port' : fallbackName),
      host: host.toLowerCase(),
      port: port,
      params: params,
    );
  }

  ProxyNode _parseModern(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null) {
      throw const LinkFormatException(
        'vmess:// link is neither base64 nor uuid@host:port',
      );
    }
    final uuid = link.decodedUserInfo.trim();
    if (uuid.isEmpty) {
      throw const LinkFormatException('vmess:// link carries no user id');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException('vmess:// link carries no server port');
    }
    final params = <String, Object?>{
      ParamKeys.uuid: uuid,
      ParamKeys.alterId: link.query.firstOf(<String>['aid', 'alterid']) ?? '0',
      ParamKeys.vmessSecurity:
          link.query.firstOf(<String>['scy', 'encryption']) ?? 'auto',
    };
    TransportParams.readInto(
      params,
      link.query,
      defaultSecurity: ParamKeys.securityNone,
      uriPath: link.path,
    );
    return NodeFactory.build(
      protocol: Protocol.vmess,
      name: link.name,
      host: link.host,
      port: port,
      params: params,
    );
  }

  static String? _text(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is int) {
      return '$value';
    }
    if (value is double) {
      return value == value.roundToDouble() ? '${value.toInt()}' : '$value';
    }
    if (value is bool) {
      return value ? 'true' : 'false';
    }
    return null;
  }
}
