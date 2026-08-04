import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/percent.dart';
import 'package:commy_config/src/internal/query_map.dart';

/// A proxy link taken apart by hand.
///
/// `Uri.parse` is not usable here. Half the links in a real subscription are
/// not valid URIs: `ss://` puts raw base64 where the authority belongs,
/// passwords contain unescaped `@` and `:`, hosts arrive upper-cased and
/// ports arrive with spaces around them. Everything below is therefore split
/// on delimiters and validated afterwards, not before.
class RawLink {
  /// Creates a link from already-split parts.
  const RawLink({
    required this.scheme,
    required this.userInfo,
    required this.address,
    required this.path,
    required this.query,
    required this.fragment,
    required this.body,
  });

  /// Splits [raw] into its parts, or returns `null` when it is not a link.
  ///
  /// The scheme is lower-cased, the fragment is percent-decoded, the user
  /// info is left verbatim because only the protocol parser knows whether it
  /// is a password, a base64 blob or a `uuid:password` pair.
  static RawLink? tryParse(String raw) {
    final trimmed = raw.trim();
    final separator = trimmed.indexOf('://');
    if (separator <= 0) {
      return null;
    }
    final scheme = trimmed.substring(0, separator).trim().toLowerCase();
    if (!_schemePattern.hasMatch(scheme)) {
      return null;
    }
    var rest = trimmed.substring(separator + 3);

    var fragment = '';
    final hash = rest.indexOf('#');
    if (hash >= 0) {
      fragment = Percent.decode(rest.substring(hash + 1)).trim();
      rest = rest.substring(0, hash);
    }
    final body = rest;

    var query = QueryMap.empty;
    final question = rest.indexOf('?');
    if (question >= 0) {
      query = QueryMap.parse(rest.substring(question + 1));
      rest = rest.substring(0, question);
    }

    var path = '';
    final slash = rest.indexOf('/');
    if (slash >= 0) {
      path = rest.substring(slash);
      rest = rest.substring(0, slash);
    }

    var userInfo = '';
    final at = rest.lastIndexOf('@');
    if (at >= 0) {
      userInfo = rest.substring(0, at);
      rest = rest.substring(at + 1);
    }

    final address = HostPort.tryParse(rest);
    if (address == null || !HostPort.isPlausibleHost(address.host)) {
      return null;
    }
    return RawLink(
      scheme: scheme,
      userInfo: userInfo,
      address: address,
      path: path,
      query: query,
      fragment: fragment,
      body: body,
    );
  }

  /// Whether [raw] starts with `<something>://`.
  static bool hasScheme(String raw) =>
      _schemeLinePattern.hasMatch(raw.trimLeft());

  /// Returns the lower-cased scheme of [raw], or `null`.
  static String? schemeOf(String raw) {
    final trimmed = raw.trim();
    final separator = trimmed.indexOf('://');
    if (separator <= 0) {
      return null;
    }
    final scheme = trimmed.substring(0, separator).trim().toLowerCase();
    return _schemePattern.hasMatch(scheme) ? scheme : null;
  }

  static final RegExp _schemePattern = RegExp(r'^[a-z][a-z0-9+.\-]*$');

  static final RegExp _schemeLinePattern =
      RegExp(r'^[A-Za-z][A-Za-z0-9+.\-]*://');

  /// Lower-cased scheme, without `://`.
  final String scheme;

  /// Everything between `://` and the last `@`, verbatim.
  final String userInfo;

  /// Host and port.
  final HostPort address;

  /// Path including the leading slash, or an empty string.
  final String path;

  /// Parsed query string.
  final QueryMap query;

  /// Percent-decoded fragment, which is where panels put the node name.
  final String fragment;

  /// Everything after `://` and before `#`, verbatim.
  ///
  /// Needed by `vmess://` and `ss://`, whose legacy forms put base64 where a
  /// URI expects an authority.
  final String body;

  /// Server host, never bracketed.
  String get host => address.host;

  /// Server port, or `null` when the link omitted it.
  int? get port => address.port;

  /// [userInfo] with percent-escapes resolved.
  String get decodedUserInfo => Percent.decode(userInfo);

  /// The node name: the fragment, falling back to the host.
  String get name => fragment.isEmpty ? host : fragment;

  @override
  String toString() => 'RawLink($scheme, ${address.authority})';
}
