import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `shadowtls://` links.
///
/// ShadowTLS has no blessed share-link format; this is the shape the clients
/// that emit one have settled on:
///
/// ```text
/// shadowtls://<password>@host:443?version=3&sni=www.example.com#name
/// ```
///
/// It is supported mainly so that a ShadowTLS entry inside a Clash or
/// sing-box document can be exported again without losing anything.
class ShadowtlsLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const ShadowtlsLinkParser();

  /// Protocol versions the core implements.
  static const Set<String> supportedVersions = <String>{'1', '2', '3'};

  @override
  Set<String> get schemes => const <String>{'shadowtls'};

  @override
  Protocol get protocol => Protocol.shadowtls;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || link.scheme != 'shadowtls') {
      throw const LinkFormatException('Not a shadowtls:// link');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException(
        'shadowtls:// link carries no server port',
      );
    }
    final declared = link.query.first('version');
    final version = supportedVersions.contains(declared) ? declared : '3';
    final password = link.decodedUserInfo.trim().isNotEmpty
        ? link.decodedUserInfo.trim()
        : link.query.first('password');
    if (version != '1' && (password == null || password.isEmpty)) {
      throw const LinkFormatException(
        'shadowtls:// version 2 and 3 need a password',
      );
    }
    return NodeFactory.build(
      protocol: Protocol.shadowtls,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.password: password,
        ParamKeys.version: version,
        ParamKeys.sni: link.query.firstOf(<String>['sni', 'servername']),
        ParamKeys.alpn: link.query.csv('alpn').join(','),
        ParamKeys.allowInsecure: link.query.flagOf(
          <String>['insecure', 'allowinsecure', 'skip-cert-verify'],
          orElse: false,
        ),
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final password = node.param(ParamKeys.password) ?? '';
    final entries = <MapEntry<String, String>>[
      MapEntry<String, String>('version', node.param(ParamKeys.version) ?? '3'),
    ];
    void add(String key, String? value) {
      if (value != null && value.isNotEmpty && value != 'false') {
        entries.add(
          MapEntry<String, String>(key, value == 'true' ? '1' : value),
        );
      }
    }

    add('sni', node.param(ParamKeys.sni));
    add('alpn', node.param(ParamKeys.alpn));
    add('insecure', node.param(ParamKeys.allowInsecure));
    final query = entries
        .map((e) => '${e.key}=${Percent.encodeQueryValue(e.value)}')
        .join('&');
    final userInfo = password.isEmpty ? '' : '${Percent.encode(password)}@';
    return 'shadowtls://$userInfo$address:${node.port}?$query'
        '#${Percent.encodeFragment(node.name)}';
  }
}
