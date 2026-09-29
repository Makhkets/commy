import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';

/// Writes a second XHTTP route in the one shape the app stores: Xray's
/// `downloadSettings`, a `streamSettings` with `address` and `port` added.
///
/// Clash.Meta and the sing-box forks describe the route in shapes of their
/// own. Their readers turn it into node parameters with the code they already
/// have for a whole server, and hand those here — so the node carries the
/// route as a link does, a link exported from it is one Xray reads, and the
/// builder has one shape to read.
abstract final class XhttpDownloadSettings {
  /// Commy's key in a stored `tlsSettings` for sing-box's `disable_sni`.
  static const String disableSniKey = 'disableSNI';

  /// The route to [address] (and [port], when known; the builder uses the
  /// main route's otherwise), described by [params]: security, SNI, ALPN,
  /// fingerprint, Reality keys, host, path, mode and `extra`, keyed as
  /// [ParamKeys] keys them.
  static Map<String, Object?> write({
    required String address,
    required int? port,
    required Map<String, Object?> params,
  }) {
    String? text(String key) {
      final value = params[key];
      final trimmed = value == null ? null : '$value'.trim();
      return trimmed == null || trimmed.isEmpty ? null : trimmed;
    }

    final security = text(ParamKeys.security)?.toLowerCase();
    final route = <String, Object?>{
      'address': address,
      if (port != null && port > 0) 'port': port,
      'network': 'xhttp',
      'security': switch (security) {
        ParamKeys.securityReality => 'reality',
        ParamKeys.securityTls => 'tls',
        _ => 'none',
      },
    };

    if (security == ParamKeys.securityTls) {
      final alpn = text(ParamKeys.alpn);
      route['tlsSettings'] = <String, Object?>{
        if (text(ParamKeys.sni) != null) 'serverName': text(ParamKeys.sni),
        if (alpn != null)
          'alpn': <String>[
            for (final part in alpn.split(','))
              if (part.trim().isNotEmpty) part.trim(),
          ],
        if (text(ParamKeys.fingerprint) != null)
          'fingerprint': text(ParamKeys.fingerprint),
        if (_flag(params[ParamKeys.allowInsecure])) 'allowInsecure': true,
        // Xray has no such switch and ignores a key it does not know; the
        // sing-box block the route may have come from has one, and a route
        // that sent no SNI must not start sending it.
        if (_flag(params[ParamKeys.disableSni])) disableSniKey: true,
      };
    } else if (security == ParamKeys.securityReality) {
      route['realitySettings'] = <String, Object?>{
        if (text(ParamKeys.sni) != null) 'serverName': text(ParamKeys.sni),
        if (text(ParamKeys.fingerprint) != null)
          'fingerprint': text(ParamKeys.fingerprint),
        if (text(ParamKeys.publicKey) != null)
          'publicKey': text(ParamKeys.publicKey),
        if (text(ParamKeys.shortId) != null) 'shortId': text(ParamKeys.shortId),
        if (text(ParamKeys.spiderX) != null) 'spiderX': text(ParamKeys.spiderX),
      };
    }

    // A route of its own inside the route is never read (see
    // XrayStreamReader.readInto) and is not carried on.
    final settings = XhttpSettings.tryParseExtra(text(ParamKeys.extra))
        ?.withDownloadSettings(null);
    route['xhttpSettings'] = <String, Object?>{
      if (text(ParamKeys.host) != null) 'host': text(ParamKeys.host),
      if (text(ParamKeys.path) != null) 'path': text(ParamKeys.path),
      // Never used for the download, but the rules the route's own settings
      // are checked by depend on it, in Xray as here.
      if (text(ParamKeys.mode) != null) 'mode': text(ParamKeys.mode),
      if (settings != null && !settings.isEmpty) 'extra': settings.toXray(),
    };
    return route;
  }

  static bool _flag(Object? value) =>
      value == true || '$value'.toLowerCase() == 'true' || '$value' == '1';
}
