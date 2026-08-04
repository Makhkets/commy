import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `trojan://` links.
///
/// ```text
/// trojan://<password>@host:443?security=tls&sni=..&type=ws&path=/x#name
/// ```
///
/// Trojan is TLS by definition, so a link that says nothing about security
/// means TLS — unlike VLESS, where silence means plaintext.
class TrojanLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const TrojanLinkParser();

  @override
  Set<String> get schemes => const <String>{'trojan', 'trojan-go'};

  @override
  Protocol get protocol => Protocol.trojan;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not a trojan:// link');
    }
    final password = link.decodedUserInfo.trim();
    if (password.isEmpty) {
      throw const LinkFormatException('trojan:// link carries no password');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException('trojan:// link carries no server port');
    }
    final params = <String, Object?>{ParamKeys.password: password};
    TransportParams.readInto(
      params,
      link.query,
      defaultSecurity: ParamKeys.securityTls,
      uriPath: link.path,
    );
    return NodeFactory.build(
      protocol: Protocol.trojan,
      name: link.name,
      host: link.host,
      port: port,
      params: params,
    );
  }

  @override
  String toLink(ProxyNode node) {
    final password = node.param(ParamKeys.password);
    if (password == null || password.isEmpty) {
      throw const LinkFormatException('Node carries no password');
    }
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final query = TransportParams.buildQuery(TransportParams.writeQuery(node));
    final suffix = query.isEmpty ? '' : '?$query';
    return 'trojan://${Percent.encode(password)}@$address:${node.port}$suffix'
        '#${Percent.encodeFragment(node.name)}';
  }
}
