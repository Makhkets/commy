import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `hysteria2://` and `hy2://` links.
///
/// ```text
/// hysteria2://<password>@host:443?sni=..&insecure=1
///            &obfs=salamander&obfs-password=..#name
/// ```
///
/// The whole user info is the authentication string, including any colon in
/// it: Hysteria 2 has one credential, not a user and a password.
class Hysteria2LinkParser implements NodeLinkParser {
  /// Creates the parser.
  const Hysteria2LinkParser();

  /// Query keys that may hold the obfuscation password.
  static const List<String> obfsPasswordKeys = <String>[
    'obfs-password',
    'obfs_password',
    'obfspassword',
    'obfsparam',
  ];

  @override
  Set<String> get schemes => const <String>{'hysteria2', 'hy2'};

  @override
  Protocol get protocol => Protocol.hysteria2;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not a hysteria2:// link');
    }
    final password = link.decodedUserInfo.trim().isEmpty
        ? link.query.firstOf(<String>['auth', 'password'])
        : link.decodedUserInfo.trim();
    if (password == null || password.isEmpty) {
      throw const LinkFormatException(
        'hysteria2:// link carries no authentication string',
      );
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException(
        'hysteria2:// link carries no server port',
      );
    }
    final alpn = link.query.csv('alpn');
    return NodeFactory.build(
      protocol: Protocol.hysteria2,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.password: password,
        ParamKeys.sni: link.query.firstOf(<String>['sni', 'peer']),
        ParamKeys.alpn: alpn.isEmpty ? null : alpn.join(','),
        ParamKeys.obfs: link.query.first('obfs'),
        ParamKeys.obfsPassword: link.query.firstOf(obfsPasswordKeys),
        ParamKeys.upMbps: link.query.integerOf(<String>['up', 'upmbps']),
        ParamKeys.downMbps: link.query.integerOf(<String>['down', 'downmbps']),
        ParamKeys.serverPorts:
            link.query.firstOf(<String>['mport', 'ports', 'server_ports']),
        ParamKeys.allowInsecure: link.query.flagOf(
          <String>['insecure', 'allowinsecure', 'allow_insecure'],
          orElse: false,
        ),
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final password = node.param(ParamKeys.password);
    if (password == null || password.isEmpty) {
      throw const LinkFormatException('Node carries no authentication string');
    }
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final entries = <MapEntry<String, String>>[];
    void add(String key, String? value) {
      if (value != null && value.isNotEmpty && value != 'false') {
        entries.add(
          MapEntry<String, String>(key, value == 'true' ? '1' : value),
        );
      }
    }

    add('sni', node.param(ParamKeys.sni));
    add('alpn', node.param(ParamKeys.alpn));
    add('obfs', node.param(ParamKeys.obfs));
    add('obfs-password', node.param(ParamKeys.obfsPassword));
    add('up', node.param(ParamKeys.upMbps));
    add('down', node.param(ParamKeys.downMbps));
    add('mport', node.param(ParamKeys.serverPorts));
    add('insecure', node.param(ParamKeys.allowInsecure));
    final query = entries
        .map((e) => '${e.key}=${Percent.encodeQueryValue(e.value)}')
        .join('&');
    final suffix = query.isEmpty ? '' : '?$query';
    return 'hysteria2://${Percent.encode(password)}@$address:${node.port}'
        '$suffix#${Percent.encodeFragment(node.name)}';
  }
}
