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
///
/// The official URI scheme allows two things no other link does: the port may
/// be left out (it is then 443), and a server that hops ports puts the whole
/// list in the authority, `host:123,5000-6000`. `hysteria share` writes that
/// form, so both are read here.
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

  /// Port the URI scheme implies when the authority carries none.
  static const int defaultPort = 443;

  /// A port list in the authority: single ports and ranges, comma-separated.
  static final RegExp _portList =
      RegExp(r'^\s*\d+(\s*-\s*\d+)?(\s*,\s*\d+(\s*-\s*\d+)?)*\s*$');

  static final RegExp _digits = RegExp(r'\d+');

  @override
  Set<String> get schemes => const <String>{'hysteria2', 'hy2'};

  @override
  Protocol get protocol => Protocol.hysteria2;

  @override
  ProxyNode parse(String raw) {
    final (:link, :hopList) = _splitHopAuthority(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not a hysteria2:// link');
    }
    final password = link.decodedUserInfo.trim().isEmpty
        ? link.query.firstOf(<String>['auth', 'password'])
        : link.decodedUserInfo.trim();
    if (password == null || password.isEmpty) {
      throw const LinkFormatException.incomplete(
        'hysteria2:// link carries no authentication string',
      );
    }
    final port = link.port ?? defaultPort;
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
        // An explicit `mport` is the more deliberate of the two: it wins.
        ParamKeys.serverPorts:
            link.query.firstOf(<String>['mport', 'ports', 'server_ports']) ??
                hopList,
        ParamKeys.allowInsecure: link.query.flagOf(
          <String>['insecure', 'allowinsecure', 'allow_insecure'],
          orElse: false,
        ),
      },
    );
  }

  /// Takes a port list out of the authority, which the shared [RawLink]
  /// would refuse as a malformed port.
  ///
  /// The link keeps the first port of the list (the start of the first
  /// range), which is where the client connects before it starts hopping, and
  /// the list itself comes back without whitespace. A link without a list is
  /// parsed as it is.
  static ({RawLink? link, String? hopList}) _splitHopAuthority(String raw) {
    final start = raw.indexOf('://');
    if (start <= 0) {
      return (link: RawLink.tryParse(raw), hopList: null);
    }
    final authorityStart = start + 3;
    var authorityEnd = raw.length;
    for (final delimiter in const <String>['/', '?', '#']) {
      final index = raw.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) {
        authorityEnd = index;
      }
    }
    final authority = raw.substring(authorityStart, authorityEnd);
    final hostStart = authority.lastIndexOf('@') + 1;
    final address = authority.substring(hostStart);
    final int colon;
    if (address.trimLeft().startsWith('[')) {
      final close = address.indexOf(']:');
      colon = close < 0 ? -1 : close + 1;
    } else {
      colon = address.lastIndexOf(':');
      // More than one colon and no brackets is a bare IPv6 literal.
      if (colon >= 0 && address.substring(0, colon).contains(':')) {
        return (link: RawLink.tryParse(raw), hopList: null);
      }
    }
    final ports = colon < 0 ? '' : address.substring(colon + 1);
    final isList = (ports.contains(',') || ports.contains('-')) &&
        _portList.hasMatch(ports);
    if (!isList) {
      return (link: RawLink.tryParse(raw), hopList: null);
    }
    final first = _digits.firstMatch(ports)!.group(0)!;
    final portStart = authorityStart + hostStart + colon + 1;
    final rewritten = raw.replaceRange(portStart, authorityEnd, first);
    return (
      link: RawLink.tryParse(rewritten),
      hopList: ports.replaceAll(RegExp(r'\s'), ''),
    );
  }

  @override
  String toLink(ProxyNode node) {
    final password = node.param(ParamKeys.password);
    if (password == null || password.isEmpty) {
      throw const LinkFormatException.incomplete(
        'Node carries no authentication string',
      );
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
