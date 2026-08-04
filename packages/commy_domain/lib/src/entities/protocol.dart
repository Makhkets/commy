/// Wire protocol of a proxy server.
///
/// [wireName] is the `type` the sing-box core expects in an outbound.
/// [schemes] lists the URI schemes an import may use for it, canonical first.
enum Protocol {
  /// VLESS, including the Reality transport.
  vless(wireName: 'vless', schemes: <String>['vless']),

  /// VMess.
  vmess(wireName: 'vmess', schemes: <String>['vmess']),

  /// Trojan.
  trojan(wireName: 'trojan', schemes: <String>['trojan', 'trojan-go']),

  /// Shadowsocks, both the legacy and the SIP002 link format.
  shadowsocks(wireName: 'shadowsocks', schemes: <String>['ss', 'shadowsocks']),

  /// Hysteria 2.
  hysteria2(wireName: 'hysteria2', schemes: <String>['hysteria2', 'hy2']),

  /// TUIC.
  tuic(wireName: 'tuic', schemes: <String>['tuic']),

  /// WireGuard.
  wireguard(wireName: 'wireguard', schemes: <String>['wireguard', 'wg']),

  /// ShadowTLS.
  shadowtls(wireName: 'shadowtls', schemes: <String>['shadowtls']),

  /// Plain SOCKS, mostly useful for local debugging.
  socks(wireName: 'socks', schemes: <String>['socks', 'socks5']),

  /// Plain HTTP proxy, mostly useful for local debugging.
  http(wireName: 'http', schemes: <String>['http', 'https']);

  const Protocol({required this.wireName, required this.schemes});

  /// Outbound `type` understood by the sing-box core.
  final String wireName;

  /// URI schemes that map onto this protocol, canonical one first.
  final List<String> schemes;

  /// The scheme we emit when exporting a node as a link.
  String get canonicalScheme => schemes.first;

  /// Returns the protocol registered for [scheme], or `null` if there is none.
  ///
  /// Accepts `vless`, `VLESS:`, `vless://` and anything in between.
  static Protocol? fromScheme(String scheme) {
    final normalised = scheme.toLowerCase().replaceAll(RegExp('[:/]'), '');
    if (normalised.isEmpty) {
      return null;
    }
    for (final protocol in Protocol.values) {
      if (protocol.schemes.contains(normalised)) {
        return protocol;
      }
    }
    return null;
  }

  /// Returns the protocol whose [wireName] is [name], or `null`.
  static Protocol? fromWireName(String name) {
    final normalised = name.toLowerCase();
    for (final protocol in Protocol.values) {
      if (protocol.wireName == normalised) {
        return protocol;
      }
    }
    return null;
  }
}
