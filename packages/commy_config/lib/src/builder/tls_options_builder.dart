import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
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
///   whether or not the link named one — and it is always Chrome's, see
///   [realityFingerprint].
/// * `server_name` is filled from the host when the link gave no SNI, but only
///   when the host is a name. Sending an IP literal as SNI is invalid.
abstract final class TlsOptionsBuilder {
  /// Fingerprint used when Reality is on and the link named none.
  static const String defaultFingerprint = realityFingerprint;

  /// The fingerprint every Reality connection is made with, whatever the link
  /// named.
  ///
  /// Xray 26.9.8 and later refuse a Reality ClientHello without an
  /// `X25519MLKEM768` key share, and in the uTLS the pinned core is built with
  /// (metacubex/utls v1.8.4) only the Chrome hellos carry one. Measured with
  /// the pinned core and the stand (docs/18) against Xray 26.9.9: `chrome`
  /// connects; `firefox`, `safari`, `ios`, `edge`, `qq` and `random` are
  /// answered with the decoy's certificate; `randomized` carries the share
  /// only when its coin lands that way; `android` and `360` offer no X25519
  /// at all and fail against every Xray, old ones included. Against Xray
  /// 26.3.27 all of them but those two connect — which is why a link that
  /// names `firefox` worked yesterday and does not after the server updated.
  ///
  /// A Reality server does not check the fingerprint; it is there to blend
  /// in, and Chrome is the most common hello there is. So the builder uses it
  /// for Reality always, and older servers are reached with it too — the
  /// overlay's second attempt strips the share they cannot take
  /// (docs/adr/0011-reality-client-hello.md). The link itself keeps what the
  /// panel wrote: export and QR hand on the original `fp`. Narrow this again
  /// when a core bump brings a uTLS with the share in the other hellos.
  static const String realityFingerprint = 'chrome';

  /// Longest a Reality short id may be: eight bytes, written as hex.
  static const int maxShortIdLength = 16;

  static final RegExp _hex = RegExp(r'^[0-9a-fA-F]*$');

  /// Builds the block for [node], or returns `null` when TLS is off.
  ///
  /// [alwaysOn] is for the protocols that are TLS by construction — Hysteria 2
  /// and TUIC run over QUIC and have no plaintext mode.
  ///
  /// [overQuic] is for whatever ends up on QUIC: those two, and XHTTP when its
  /// ALPN is `h3`. uTLS imitates a browser's TLS-over-TCP handshake and has
  /// nothing to say about QUIC; the core answers a `utls` block there with
  /// "unsupported usage for uTLS" on every single connection. A fingerprint in
  /// the link is therefore left out rather than passed on — Xray ignores it in
  /// the same place.
  static Map<String, Object?>? build(
    ProxyNode node, {
    bool alwaysOn = false,
    bool overQuic = false,
  }) {
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
        SingBoxKeys.fingerprint: realityFingerprint,
      };
      options[SingBoxKeys.reality] = _reality(node);
    } else if (!overQuic && fingerprint != null && fingerprint.isNotEmpty) {
      options[SingBoxKeys.utls] = <String, Object?>{
        SingBoxKeys.enabled: true,
        SingBoxKeys.fingerprint: fingerprint,
      };
    }

    return options;
  }

  /// Whether [node] is XHTTP over HTTP/3, which is to say over QUIC.
  ///
  /// The version is picked the way the transport picks it: a single ALPN entry
  /// `h3` means HTTP/3, anything else is HTTP/2 or HTTP/1.1 over TCP. Reality
  /// is always HTTP/2, whatever the ALPN says.
  static bool isXhttpOverQuic(ProxyNode node) {
    if (node.param(ParamKeys.transport) != TransportParams.xhttp) {
      return false;
    }
    if (node.param(ParamKeys.security)?.toLowerCase() ==
        ParamKeys.securityReality) {
      return false;
    }
    final alpn = readAlpn(node);
    return alpn.length == 1 && alpn.single.toLowerCase() == 'h3';
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
