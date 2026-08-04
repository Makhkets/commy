import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `tuic://` links.
///
/// ```text
/// tuic://<uuid>:<password>@host:443?congestion_control=bbr
///       &alpn=h3&sni=..&udp_relay_mode=native#name
/// ```
///
/// The user info is a pair here, unlike Hysteria 2: everything before the
/// first colon is the identifier, everything after it is the password.
class TuicLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const TuicLinkParser();

  /// Congestion controllers the core accepts.
  static const Set<String> congestionControllers = <String>{
    'cubic',
    'new_reno',
    'bbr',
  };

  @override
  Set<String> get schemes => const <String>{'tuic'};

  @override
  Protocol get protocol => Protocol.tuic;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || link.scheme != 'tuic') {
      throw const LinkFormatException('Not a tuic:// link');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException('tuic:// link carries no server port');
    }
    final userInfo = link.userInfo;
    final colon = userInfo.indexOf(':');
    final uuid = Percent.decode(
      colon < 0 ? userInfo : userInfo.substring(0, colon),
    ).trim();
    final password = colon < 0
        ? link.query.first('password') ?? ''
        : Percent.decode(userInfo.substring(colon + 1));
    if (uuid.isEmpty) {
      throw const LinkFormatException('tuic:// link carries no user id');
    }
    final controller = link.query.firstOf(
      <String>['congestion_control', 'congestion-controller'],
    )?.toLowerCase();
    final alpn = link.query.csv('alpn');
    return NodeFactory.build(
      protocol: Protocol.tuic,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.uuid: uuid,
        ParamKeys.password: password,
        ParamKeys.sni: link.query.firstOf(<String>['sni', 'peer']),
        ParamKeys.alpn: alpn.isEmpty ? null : alpn.join(','),
        ParamKeys.congestionControl:
            congestionControllers.contains(controller) ? controller : null,
        ParamKeys.udpRelayMode:
            link.query.firstOf(<String>['udp_relay_mode', 'udp-relay-mode']),
        ParamKeys.allowInsecure: link.query.flagOf(
          <String>['insecure', 'allowinsecure', 'allow_insecure'],
          orElse: false,
        ),
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final uuid = node.param(ParamKeys.uuid);
    if (uuid == null || uuid.isEmpty) {
      throw const LinkFormatException('Node carries no user id');
    }
    final password = node.param(ParamKeys.password) ?? '';
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
    add('congestion_control', node.param(ParamKeys.congestionControl));
    add('udp_relay_mode', node.param(ParamKeys.udpRelayMode));
    add('allow_insecure', node.param(ParamKeys.allowInsecure));
    final query = entries
        .map((e) => '${e.key}=${Percent.encodeQueryValue(e.value)}')
        .join('&');
    final suffix = query.isEmpty ? '' : '?$query';
    return 'tuic://${Percent.encode(uuid)}:${Percent.encode(password)}'
        '@$address:${node.port}$suffix'
        '#${Percent.encodeFragment(node.name)}';
  }
}
