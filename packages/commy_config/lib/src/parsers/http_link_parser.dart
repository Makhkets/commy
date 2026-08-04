import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/raw_link.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `http://` and `https://` proxy links.
///
/// This scheme is shared with the rest of the web, which is the whole
/// problem: a subscription URL and an HTTP proxy look identical to a parser.
/// [looksLikeProxy] is the tie-breaker, and the multi-line importer consults
/// it before handing a line here, so that pasting a subscription URL is never
/// silently turned into a proxy node pointing at a panel.
class HttpLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const HttpLinkParser();

  @override
  Set<String> get schemes => const <String>{'http', 'https'};

  @override
  Protocol get protocol => Protocol.http;

  /// Whether [raw] is an HTTP proxy rather than an ordinary web address.
  ///
  /// A proxy always names its port, and never has a path: `http://1.2.3.4:8080`
  /// or `https://user:pass@proxy.example:3128`. A subscription URL is the
  /// other way round — it leans on the default port and carries a token in
  /// the path.
  static bool looksLikeProxy(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || link.port == null) {
      return false;
    }
    return link.path.isEmpty || link.path == '/';
  }

  @override
  ProxyNode parse(String raw) {
    final link = RawLink.tryParse(raw);
    if (link == null || !schemes.contains(link.scheme)) {
      throw const LinkFormatException('Not an http:// proxy link');
    }
    final port = link.port;
    if (port == null) {
      throw const LinkFormatException(
        'http:// proxy link carries no server port',
      );
    }
    if (link.path.isNotEmpty && link.path != '/') {
      throw const LinkFormatException(
        'Looks like a subscription address, not an HTTP proxy',
      );
    }
    final credentials = _readCredentials(link.userInfo);
    final secure = link.scheme == 'https';
    return NodeFactory.build(
      protocol: Protocol.http,
      name: link.name,
      host: link.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.username: credentials.key,
        ParamKeys.password: credentials.value,
        ParamKeys.security:
            secure ? ParamKeys.securityTls : ParamKeys.securityNone,
        ParamKeys.sni: link.query.first('sni'),
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
    final user = node.param(ParamKeys.username);
    final password = node.param(ParamKeys.password);
    final userInfo = user == null || user.isEmpty
        ? ''
        : '${Percent.encode(user)}:${Percent.encode(password ?? '')}@';
    final secure = node.param(ParamKeys.security) == ParamKeys.securityTls;
    final scheme = secure ? 'https' : 'http';
    return '$scheme://$userInfo$address:${node.port}'
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
