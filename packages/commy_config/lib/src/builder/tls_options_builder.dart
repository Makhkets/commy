import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `tls` block of an outbound.
///
/// Mirrors `option.OutboundTLSOptions` at tag v1.13.16. Three things here are
/// not obvious and all three come straight from the core's source:
///
/// * Reality has **exactly three** fields — `enabled`, `public_key`,
///   `short_id`. The `spx` parameter a link may carry has no home in the
///   configuration and is dropped (docs/13-libbox-reference.md).
/// * Reality **requires** uTLS: `reality_client.go` refuses to start with
///   "uTLS is required by reality client", so the fingerprint block is written
///   whether or not the link named one.
/// * `server_name` is filled from the host when the link gave no SNI, but only
///   when the host is a name. Sending an IP literal as SNI is invalid.
abstract final class TlsOptionsBuilder {
  /// Fingerprint used when Reality is on and the link named none.
  static const String defaultFingerprint = 'chrome';

  /// Longest a Reality short id may be: eight bytes, written as hex.
  static const int maxShortIdLength = 16;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]*$');

  /// Builds the block for [node], or returns `null` when TLS is off.
  ///
  /// [alwaysOn] is for the protocols that are TLS by construction — Hysteria 2
  /// and TUIC run over QUIC and have no plaintext mode.
  static Map<String, Object?>? build(ProxyNode node, {bool alwaysOn = false}) {
    final security = node.param(ParamKeys.security)?.toLowerCase();
    final isReality = security == ParamKeys.securityReality;
    final isTls = alwaysOn || isReality || security == ParamKeys.securityTls;
    if (!isTls) {
      return null;
    }

    final options = <String, Object?>{SingBoxKeys.enabled: true};

    final serverName = resolveServerName(node);
    if (serverName != null) {
      options[SingBoxKeys.serverName] = serverName;
    } else if (isReality) {
      throw const ConfigBuildException(
        'Reality needs a server name: the link carried neither sni nor a '
        'hostname',
      );
    }

    if (_flag(node, ParamKeys.allowInsecure)) {
      options[SingBoxKeys.insecure] = true;
    }
    if (_flag(node, ParamKeys.disableSni)) {
      options[SingBoxKeys.disableSni] = true;
    }

    final alpn = readAlpn(node);
    if (alpn.isNotEmpty) {
      options[SingBoxKeys.alpn] = alpn;
    }

    final fingerprint = node.param(ParamKeys.fingerprint);
    if (isReality) {
      options[SingBoxKeys.utls] = <String, Object?>{
        SingBoxKeys.enabled: true,
        SingBoxKeys.fingerprint: fingerprint == null || fingerprint.isEmpty
            ? defaultFingerprint
            : fingerprint,
      };
      options[SingBoxKeys.reality] = _reality(node);
    } else if (fingerprint != null && fingerprint.isNotEmpty) {
      options[SingBoxKeys.utls] = <String, Object?>{
        SingBoxKeys.enabled: true,
        SingBoxKeys.fingerprint: fingerprint,
      };
    }

    return options;
  }

  /// The SNI to send: the declared one, else the host when it is a name.
  static String? resolveServerName(ProxyNode node) {
    final sni = node.param(ParamKeys.sni);
    if (sni != null && sni.isNotEmpty) {
      return sni;
    }
    return isIpLiteral(node.host) ? null : node.host;
  }

  /// The negotiated protocol list, split out of the comma separated param.
  static List<String> readAlpn(ProxyNode node) {
    final raw = node.param(ParamKeys.alpn);
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return <String>[
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  /// Whether [host] is an address rather than a name.
  static bool isIpLiteral(String host) {
    if (host.contains(':')) {
      return true;
    }
    final parts = host.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final value = int.tryParse(part);
      if (value == null || value < 0 || value > 255) {
        return false;
      }
    }
    return true;
  }

  static Map<String, Object?> _reality(ProxyNode node) {
    final publicKey = node.param(ParamKeys.publicKey);
    if (publicKey == null || publicKey.isEmpty) {
      throw const ConfigBuildException('Reality needs a public key');
    }
    final reality = <String, Object?>{
      SingBoxKeys.enabled: true,
      SingBoxKeys.publicKey: publicKey,
    };
    final shortId = node.param(ParamKeys.shortId);
    if (shortId != null && shortId.isNotEmpty) {
      if (shortId.length > maxShortIdLength || !_hex.hasMatch(shortId)) {
        throw const ConfigBuildException(
          'Reality short id must be at most $maxShortIdLength hex characters',
        );
      }
      reality[SingBoxKeys.shortId] = shortId;
    }
    return reality;
  }

  static bool _flag(ProxyNode node, String key) {
    final value = node.params[key];
    if (value is bool) {
      return value;
    }
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1';
  }
}
