/// The canonical names of everything stored in `ProxyNode.params`.
///
/// One list, used by the parsers, the config builder and the exporter, so a
/// key can never be written under one spelling and read under another.
///
/// Anything credential-like here must lower-case to a member of
/// `ProxyNode.secretParamKeys`, otherwise it escapes redaction (rule R3) and
/// the plain-database split (rule R2).
abstract final class ParamKeys {
  /// VLESS / VMess / TUIC user id.
  static const String uuid = 'uuid';

  /// Trojan, Shadowsocks, Hysteria 2, TUIC, SOCKS and HTTP secret.
  static const String password = 'password';

  /// SOCKS and HTTP user name.
  static const String username = 'username';

  /// Shadowsocks cipher.
  static const String method = 'method';

  /// VLESS sub-protocol, currently only `xtls-rprx-vision`.
  static const String flow = 'flow';

  /// VLESS encryption field, which is always `none` in practice.
  static const String encryption = 'encryption';

  /// VMess cipher: `auto`, `aes-128-gcm`, `chacha20-poly1305`, `none`.
  static const String vmessSecurity = 'scy';

  /// VMess legacy user count. Zero means AEAD.
  static const String alterId = 'alterId';

  /// Transport security: `none`, `tls` or `reality`.
  static const String security = 'security';

  /// Transport: `tcp`, `ws`, `grpc`, `http`, `httpupgrade`, `quic`, `xhttp`.
  static const String transport = 'type';

  /// TLS server name.
  static const String sni = 'sni';

  /// Negotiated protocols, comma separated.
  static const String alpn = 'alpn';

  /// uTLS fingerprint, for example `chrome`.
  static const String fingerprint = 'fp';

  /// Reality public key.
  static const String publicKey = 'pbk';

  /// Reality short id. Secret enough to be redacted.
  static const String shortId = 'sid';

  /// Reality spider URL. Client side ignores it; kept so re-export is lossless.
  static const String spiderX = 'spx';

  /// Whether certificate verification is switched off.
  static const String allowInsecure = 'allowInsecure';

  /// Whether the server name is withheld from ClientHello.
  static const String disableSni = 'disableSni';

  /// WebSocket, HTTP and xhttp path, or the Shadowsocks plugin path.
  static const String path = 'path';

  /// `Host` header of the WebSocket, HTTP or httpupgrade transport.
  static const String host = 'host';

  /// gRPC service name.
  static const String serviceName = 'serviceName';

  /// TCP header obfuscation type, for example `http`.
  static const String headerType = 'headerType';

  /// gRPC or xhttp mode.
  static const String mode = 'mode';

  /// Shadowsocks SIP003 plugin name.
  static const String plugin = 'plugin';

  /// Shadowsocks SIP003 plugin options, verbatim.
  static const String pluginOpts = 'pluginOpts';

  /// Hysteria 2 obfuscation type, currently only `salamander`.
  static const String obfs = 'obfs';

  /// Hysteria 2 obfuscation password.
  static const String obfsPassword = 'obfs-password';

  /// Hysteria 2 declared uplink, in Mbps.
  static const String upMbps = 'upMbps';

  /// Hysteria 2 declared downlink, in Mbps.
  static const String downMbps = 'downMbps';

  /// Hysteria 2 port hopping range, for example `2080:3000`.
  static const String serverPorts = 'serverPorts';

  /// TUIC congestion controller: `cubic`, `new_reno` or `bbr`.
  static const String congestionControl = 'congestion_control';

  /// TUIC UDP relay mode: `native` or `quic`.
  static const String udpRelayMode = 'udp_relay_mode';

  /// TUIC UDP over stream switch.
  static const String udpOverStream = 'udp_over_stream';

  /// WireGuard local private key.
  static const String privateKey = 'private_key';

  /// WireGuard peer public key.
  static const String peerPublicKey = 'peerPublicKey';

  /// WireGuard pre-shared key.
  static const String preSharedKey = 'pre_shared_key';

  /// WireGuard local addresses, comma separated CIDRs.
  static const String localAddress = 'localAddress';

  /// WireGuard reserved bytes, comma separated.
  static const String reserved = 'reserved';

  /// WireGuard keepalive, in seconds.
  static const String keepAlive = 'keepAlive';

  /// WireGuard interface MTU.
  static const String mtu = 'mtu';

  /// ShadowTLS protocol version: 1, 2 or 3.
  static const String version = 'version';

  /// SOCKS protocol version: `4`, `4a` or `5`.
  static const String socksVersion = 'socksVersion';

  /// Whether the node also carries UDP.
  static const String udp = 'udp';

  /// Value of [security] meaning no transport encryption.
  static const String securityNone = 'none';

  /// Value of [security] meaning plain TLS.
  static const String securityTls = 'tls';

  /// Value of [security] meaning Reality.
  static const String securityReality = 'reality';
}
