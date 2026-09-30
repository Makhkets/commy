import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `vless://` links, Reality included.
///
/// ```text
/// vless://<uuid>@host:443?type=tcp&security=reality&pbk=..&fp=chrome
///        &sni=..&sid=..&spx=..&flow=xtls-rprx-vision#name
/// ```
class VlessLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const VlessLinkParser();

  /// Why the core cannot carry a VLESS user with [encryption], or `null`
  /// when it can.
  ///
  /// Xray's VLESS Encryption (`mlkem768x25519plus.native.0rtt.<key>`, which
  /// 3x-ui and Remnawave share) is a layer sing-box does not have. A node
  /// that asks for it would connect as plain VLESS and be turned away by the
  /// server every time, so it is refused by name instead. Only the scheme is
  /// named: the rest of the value is the server's key, and the reason may
  /// reach a log.
  static String? encryptionRefusal(String? encryption) {
    final value = encryption?.trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'none') {
      return null;
    }
    // The scheme is the first dot-separated part; the rest carries a key.
    // Named only when it looks like a scheme name, so a value that is a key
    // with no scheme in front of it never reaches a log (R3).
    final scheme = value.split('.').first;
    final named =
        RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(scheme) ? ' "$scheme"' : '';
    return 'VLESS encryption$named is not supported by the core';
  }

  /// Throws [LinkFormatException] when [encryption] is one the core cannot
  /// carry (see [encryptionRefusal]).
  static void requireSupportedEncryption(String? encryption) {
    final refusal = encryptionRefusal(encryption);
    if (refusal != null) {
      throw LinkFormatException(refusal);
    }
  }

  @override
  Set<String> get schemes => const <String>{'vless'};

  @override
  Protocol get protocol => Protocol.vless;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || link.scheme != 'vless') {
      throw const LinkFormatException('Not a vless:// link');
    }
    final uuid = link.decodedUserInfo.trim();
    if (uuid.isEmpty) {
      throw const LinkFormatException('vless:// link carries no user id');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException('vless:// link carries no server port');
    }
    final encryption = link.query.first('encryption');
    requireSupportedEncryption(encryption);
    final params = <String, Object?>{
      ParamKeys.uuid: uuid,
      ParamKeys.encryption: encryption,
    };
    TransportParams.readInto(
      params,
      link.query,
      defaultSecurity: ParamKeys.securityNone,
      uriPath: link.path,
    );
    return NodeFactory.build(
      protocol: Protocol.vless,
      name: link.name,
      host: link.host,
      port: port,
      params: params,
    );
  }

  @override
  String toLink(ProxyNode node) {
    final uuid = node.param(ParamKeys.uuid);
    if (uuid == null || uuid.isEmpty) {
      throw const LinkFormatException('Node carries no user id');
    }
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final query = TransportParams.buildQuery(TransportParams.writeQuery(node));
    final suffix = query.isEmpty ? '' : '?$query';
    return 'vless://${Percent.encode(uuid)}@$address:${node.port}$suffix'
        '#${Percent.encodeFragment(node.name)}';
  }
}
