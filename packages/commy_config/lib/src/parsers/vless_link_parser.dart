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
    final params = <String, Object?>{
      ParamKeys.uuid: uuid,
      ParamKeys.encryption: link.query.first('encryption'),
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
