import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `socks://` and `socks5://` links.
///
/// Mostly useful for local debugging, which is exactly why it exists: being
/// able to point the app at a SOCKS proxy on `127.0.0.1` is how a routing bug
/// gets isolated from a protocol bug.
///
/// The user info is accepted both plain (`user:pass`) and base64-wrapped,
/// because both are in circulation.
class SocksLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const SocksLinkParser();

  /// SOCKS versions the core understands.
  static const Set<String> versions = <String>{'4', '4a', '5'};

  @override
  Set<String> get schemes => const <String>{'socks', 'socks5', 'socks4'};

  @override
  Protocol get protocol => Protocol.socks;

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not a socks:// link');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException('socks:// link carries no server port');
    }
    final credentials = _readCredentials(link.userInfo);
    final declared = link.query.first('version')?.toLowerCase();
    final fallback = link.scheme == 'socks4' ? '4' : '5';
    final version = versions.contains(declared) ? declared : fallback;
    return NodeFactory.build(
      protocol: Protocol.socks,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.username: credentials.key,
        ParamKeys.password: credentials.value,
        ParamKeys.socksVersion: version,
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final user = node.param(ParamKeys.username);
    final password = node.param(ParamKeys.password);
    final userInfo = user == null || user.isEmpty
        ? ''
        : '${Percent.encode(user)}:${Percent.encode(password ?? '')}@';
    return 'socks5://$userInfo$address:${node.port}'
        '#${Percent.encodeFragment(node.name)}';
  }

  static MapEntry<String, String> _readCredentials(String rawUserInfo) {
    if (rawUserInfo.isEmpty) {
      return const MapEntry<String, String>('', '');
    }
    final decoded = LenientBase64.decodeToString(rawUserInfo);
    final source = decoded != null && decoded.contains(':')
        ? decoded
        : Percent.decode(rawUserInfo);
    final colon = source.indexOf(':');
    if (colon < 0) {
      return MapEntry<String, String>(source, '');
    }
    return MapEntry<String, String>(
      source.substring(0, colon),
      source.substring(colon + 1),
    );
  }
}
