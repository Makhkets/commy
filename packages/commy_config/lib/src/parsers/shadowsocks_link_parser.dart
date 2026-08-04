import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/lenient_base64.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/query_map.dart';
import 'package:commy_config/src/parsers/node_link_parser.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `ss://` links in all three formats that circulate.
///
/// * SIP002: `ss://base64(method:password)@host:port?plugin=...#name`
/// * SIP002 with a plain user info: `ss://method:password@host:port#name`
/// * legacy: `ss://base64(method:password@host:port)#name`
///
/// Exports use SIP002 with a URL-safe, unpadded user info, which is what the
/// specification asks for and what every current client reads.
class ShadowsocksLinkParser implements NodeLinkParser {
  /// Creates the parser.
  const ShadowsocksLinkParser();

  @override
  Set<String> get schemes => const <String>{'ss', 'shadowsocks'};

  @override
  Protocol get protocol => Protocol.shadowsocks;

  @override
  ProxyNode parse(String raw) {
    final trimmed = raw.trim();
    final separator = trimmed.indexOf('://');
    if (separator <= 0 ||
        !schemes.contains(trimmed.substring(0, separator).toLowerCase())) {
      throw const LinkFormatException('Not an ss:// link');
    }
    var payload = trimmed.substring(separator + 3);
    var name = '';
    final hash = payload.indexOf('#');
    if (hash >= 0) {
      name = Percent.decode(payload.substring(hash + 1)).trim();
      payload = payload.substring(0, hash);
    }
    var query = QueryMap.empty;
    final question = payload.indexOf('?');
    if (question >= 0) {
      query = QueryMap.parse(payload.substring(question + 1));
      payload = payload.substring(0, question);
    }
    final at = payload.lastIndexOf('@');
    final credentials = at >= 0
        ? _readCredentials(payload.substring(0, at))
        : _readLegacyCredentials(payload);
    final address = at >= 0
        ? HostPort.tryParse(_stripPath(payload.substring(at + 1)))
        : credentials.address;
    if (address == null || !HostPort.isPlausibleHost(address.host)) {
      throw const LinkFormatException('ss:// link carries no server address');
    }
    final port = address.port;
    if (port == null) {
      throw const LinkFormatException('ss:// link carries no server port');
    }
    final plugin = _readPlugin(query);
    return NodeFactory.build(
      protocol: Protocol.shadowsocks,
      name: name,
      host: address.host,
      port: port,
      params: <String, Object?>{
        ParamKeys.method: credentials.method,
        ParamKeys.password: credentials.password,
        ParamKeys.plugin: plugin?.name,
        ParamKeys.pluginOpts: plugin?.options,
      },
    );
  }

  @override
  String toLink(ProxyNode node) {
    final method = node.param(ParamKeys.method);
    final password = node.param(ParamKeys.password);
    if (method == null || method.isEmpty) {
      throw const LinkFormatException('Node carries no cipher');
    }
    if (password == null || password.isEmpty) {
      throw const LinkFormatException('Node carries no password');
    }
    final userInfo = LenientBase64.encodeUrlSafe('$method:$password');
    final address = node.host.contains(':') ? '[${node.host}]' : node.host;
    final plugin = node.param(ParamKeys.plugin);
    final options = node.param(ParamKeys.pluginOpts);
    final value =
        options == null || options.isEmpty ? plugin : '$plugin;$options';
    final suffix = plugin == null || plugin.isEmpty
        ? ''
        : '?plugin=${Percent.encode(value ?? plugin)}';
    return 'ss://$userInfo@$address:${node.port}$suffix'
        '#${Percent.encodeFragment(node.name)}';
  }

  static String _stripPath(String authority) {
    final slash = authority.indexOf('/');
    return slash < 0 ? authority : authority.substring(0, slash);
  }

  static _Credentials _readCredentials(String rawUserInfo) {
    final decoded = LenientBase64.decodeToString(rawUserInfo);
    final source = decoded != null && decoded.contains(':')
        ? decoded
        : Percent.decode(rawUserInfo);
    final colon = source.indexOf(':');
    if (colon <= 0 || colon == source.length - 1) {
      throw const LinkFormatException(
        'ss:// user info is not "cipher:password"',
      );
    }
    return _Credentials(
      method: source.substring(0, colon).trim(),
      password: source.substring(colon + 1),
    );
  }

  static _Credentials _readLegacyCredentials(String payload) {
    final decoded = LenientBase64.decodeToString(payload);
    if (decoded == null) {
      throw const LinkFormatException(
        'ss:// link is neither SIP002 nor valid base64',
      );
    }
    final at = decoded.lastIndexOf('@');
    if (at <= 0) {
      throw const LinkFormatException(
        'ss:// payload is not "cipher:password@host:port"',
      );
    }
    final credentials = _readCredentials(decoded.substring(0, at));
    final address = HostPort.tryParse(decoded.substring(at + 1));
    return _Credentials(
      method: credentials.method,
      password: credentials.password,
      address: address,
    );
  }

  static _Plugin? _readPlugin(QueryMap query) {
    final raw = query.first('plugin');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final semicolon = raw.indexOf(';');
    if (semicolon < 0) {
      return _Plugin(name: raw, options: '');
    }
    return _Plugin(
      name: raw.substring(0, semicolon).trim(),
      options: raw.substring(semicolon + 1).trim(),
    );
  }
}

class _Credentials {
  const _Credentials({
    required this.method,
    required this.password,
    this.address,
  });

  final String method;
  final String password;
  final HostPort? address;
}

class _Plugin {
  const _Plugin({required this.name, required this.options});

  final String name;
  final String options;
}
