/// Every field name the generated configuration uses, in one place.
///
/// Read out of `option/*.go` at tag **v1.13.16**, the version pinned in
/// docs/13-libbox-reference.md. Two reasons this file exists:
///
/// 1. sing-box decodes the configuration with `DisallowUnknownFields`, so a
///    misspelled key is a hard startup error, not a silently ignored field.
/// 2. Several TUN keys were renamed in 1.12 (`inet4_address` and friends were
///    merged into `address`), and the old spellings still appear in every
///    tutorial on the internet. Keeping the current names here means the
///    mistake can only be made once.
///
/// Anything added here must be checked against the struct tag in the pinned
/// tag, not against memory and not against the docs site.
abstract final class SingBoxKeys {
  // ── top level (option/options.go) ──────────────────────────────────────

  /// Logging section.
  static const String log = 'log';

  /// DNS section.
  static const String dns = 'dns';

  /// Endpoints section. WireGuard lives here since 1.13.0.
  static const String endpoints = 'endpoints';

  /// Inbounds section.
  static const String inbounds = 'inbounds';

  /// Outbounds section.
  static const String outbounds = 'outbounds';

  /// Route section.
  static const String route = 'route';

  /// Experimental section.
  static const String experimental = 'experimental';

  // ── shared ────────────────────────────────────────────────────────────

  /// Discriminator of an inbound, outbound, endpoint, rule set or resolver.
  static const String type = 'type';

  /// Name a rule or another outbound can point at.
  static const String tag = 'tag';

  /// Server host. From `option.ServerOptions`.
  static const String server = 'server';

  /// Server port. From `option.ServerOptions`.
  static const String serverPort = 'server_port';

  /// Outbound a dial goes through. From `option.DialerOptions`.
  static const String detour = 'detour';

  /// Resolver used for a dial target that is a domain.
  static const String domainResolver = 'domain_resolver';

  // ── log (option/options.go, LogOptions) ───────────────────────────────

  /// Minimum severity written.
  static const String level = 'level';

  /// Whether lines carry a timestamp.
  static const String timestamp = 'timestamp';

  // ── dns (option/dns.go) ───────────────────────────────────────────────

  /// Resolver list.
  static const String servers = 'servers';

  /// Rule list. Shared spelling with `route.rules`.
  static const String rules = 'rules';

  /// Fallback resolver tag.
  static const String finalTag = 'final';

  /// Address family preference.
  static const String strategy = 'strategy';

  /// Whether each resolver keeps its own cache. Required with FakeIP.
  static const String independentCache = 'independent_cache';

  /// FakeIP IPv4 pool.
  static const String inet4Range = 'inet4_range';

  /// FakeIP IPv6 pool.
  static const String inet6Range = 'inet6_range';

  /// DNS query types a DNS rule matches.
  static const String queryType = 'query_type';

  /// Resolver a DNS rule routes to.
  static const String dnsServer = 'server';

  /// Request path of a DNS-over-HTTPS resolver.
  static const String dnsPath = 'path';

  // ── inbound: tun (option/tun.go) ──────────────────────────────────────

  /// Interface addresses. Replaced `inet4_address` / `inet6_address` in 1.12.
  static const String address = 'address';

  /// Interface MTU.
  static const String mtu = 'mtu';

  /// Whether the core installs the default routes itself.
  static const String autoRoute = 'auto_route';

  /// Whether traffic bound to another interface is forced back in.
  static const String strictRoute = 'strict_route';

  /// TUN stack: `system`, `gvisor` or `mixed`.
  static const String stack = 'stack';

  /// Extra routed prefixes. Replaced `inet4_route_address` in 1.12.
  static const String routeAddress = 'route_address';

  /// Prefixes kept out of the tunnel. Replaced the `inet4_` pair in 1.12.
  static const String routeExcludeAddress = 'route_exclude_address';

  /// Android packages routed into the tunnel.
  static const String includePackage = 'include_package';

  /// Android packages kept out of the tunnel.
  static const String excludePackage = 'exclude_package';

  // ── inbound: mixed (option/simple.go, ListenOptions) ──────────────────

  /// Listen address of a local inbound.
  static const String listen = 'listen';

  /// Listen port of a local inbound.
  static const String listenPort = 'listen_port';

  // ── outbound: shared credentials ──────────────────────────────────────

  /// VLESS, VMess and TUIC user id.
  static const String uuid = 'uuid';

  /// Trojan, Shadowsocks, Hysteria 2, TUIC, SOCKS, HTTP and ShadowTLS secret.
  static const String password = 'password';

  /// SOCKS and HTTP user name.
  static const String username = 'username';

  /// VLESS sub-protocol.
  static const String flow = 'flow';

  /// VMess cipher. Required: the struct tag has no `omitempty`.
  static const String security = 'security';

  /// VMess legacy user count.
  static const String alterId = 'alter_id';

  /// Shadowsocks cipher.
  static const String method = 'method';

  /// Shadowsocks SIP003 plugin.
  static const String plugin = 'plugin';

  /// Shadowsocks SIP003 plugin arguments.
  static const String pluginOpts = 'plugin_opts';

  /// SOCKS protocol version.
  static const String version = 'version';

  // ── outbound: hysteria2 (option/hysteria2.go) ─────────────────────────

  /// Declared uplink, in Mbps.
  static const String upMbps = 'up_mbps';

  /// Declared downlink, in Mbps.
  static const String downMbps = 'down_mbps';

  /// Port hopping ranges.
  static const String serverPorts = 'server_ports';

  /// Obfuscation block.
  static const String obfs = 'obfs';

  // ── outbound: tuic (option/tuic.go) ───────────────────────────────────

  /// Congestion controller.
  static const String congestionControl = 'congestion_control';

  /// UDP relay mode.
  static const String udpRelayMode = 'udp_relay_mode';

  /// Whether UDP is carried over a stream.
  static const String udpOverStream = 'udp_over_stream';

  // ── outbound: tls (option/tls.go) ─────────────────────────────────────

  /// TLS block.
  static const String tls = 'tls';

  /// Whether a block is switched on. Used by tls, utls and reality.
  static const String enabled = 'enabled';

  /// SNI sent in the ClientHello.
  static const String serverName = 'server_name';

  /// Whether certificate verification is skipped.
  static const String insecure = 'insecure';

  /// Whether the server name is withheld.
  static const String disableSni = 'disable_sni';

  /// Negotiated protocols.
  static const String alpn = 'alpn';

  /// uTLS block.
  static const String utls = 'utls';

  /// ClientHello fingerprint.
  static const String fingerprint = 'fingerprint';

  /// Reality block. Exactly three fields, `spider_x` is not one of them.
  static const String reality = 'reality';

  /// Reality public key.
  static const String publicKey = 'public_key';

  /// Reality short id.
  static const String shortId = 'short_id';

  // ── outbound: v2ray transport (option/v2ray_transport.go) ─────────────

  /// Transport block.
  static const String transport = 'transport';

  /// WebSocket, HTTP and httpupgrade path.
  static const String path = 'path';

  /// Extra headers.
  static const String headers = 'headers';

  /// `Host` header. A list for `http`, a plain string for `httpupgrade`.
  static const String host = 'host';

  /// gRPC service name.
  static const String serviceName = 'service_name';

  /// HTTP request method.
  static const String httpMethod = 'method';

  // ── endpoint: wireguard (option/wireguard.go) ─────────────────────────

  /// Local private key.
  static const String privateKey = 'private_key';

  /// Peer list.
  static const String peers = 'peers';

  /// Peer address. A bare host here, not `host:port`.
  static const String peerAddress = 'address';

  /// Peer port.
  static const String peerPort = 'port';

  /// Prefixes routed to a peer.
  static const String allowedIps = 'allowed_ips';

  /// Pre-shared key of a peer.
  static const String preSharedKey = 'pre_shared_key';

  /// Keepalive interval of a peer, in seconds.
  static const String persistentKeepalive = 'persistent_keepalive_interval';

  /// Reserved bytes some providers require.
  static const String reserved = 'reserved';

  // ── outbound: groups (option/group.go) ────────────────────────────────

  /// Members of a selector or urltest group.
  static const String groupOutbounds = 'outbounds';

  /// Member a selector starts on.
  static const String groupDefault = 'default';

  /// Probe a urltest group measures against.
  static const String groupUrl = 'url';

  /// How often a urltest group re-measures.
  static const String groupInterval = 'interval';

  /// How much better a member has to be before urltest switches.
  static const String groupTolerance = 'tolerance';

  // ── route (option/route.go, option/rule.go, option/rule_action.go) ────

  /// Rule set list.
  static const String ruleSet = 'rule_set';

  /// Whether the core follows the default interface.
  static const String autoDetectInterface = 'auto_detect_interface';

  /// Resolver used when a dial target is a domain and nothing else says.
  static const String defaultDomainResolver = 'default_domain_resolver';

  /// What a matched rule does.
  static const String action = 'action';

  /// Outbound a routed rule points at.
  static const String outbound = 'outbound';

  /// Whether a rule matches the private ranges.
  static const String ipIsPrivate = 'ip_is_private';

  /// Literal domain matcher.
  static const String domain = 'domain';

  /// Domain suffix matcher.
  static const String domainSuffix = 'domain_suffix';

  /// Domain substring matcher.
  static const String domainKeyword = 'domain_keyword';

  /// Domain regular expression matcher.
  static const String domainRegex = 'domain_regex';

  /// Destination prefix matcher.
  static const String ipCidr = 'ip_cidr';

  /// Destination port matcher.
  static const String port = 'port';

  /// Destination port range matcher.
  static const String portRange = 'port_range';

  /// Process name matcher. Desktop only.
  static const String processName = 'process_name';

  /// Process path matcher. Desktop only.
  static const String processPath = 'process_path';

  /// Android package matcher.
  static const String packageName = 'package_name';

  /// Sniffed protocol matcher.
  static const String protocol = 'protocol';

  /// Network matcher: `tcp` or `udp`.
  static const String network = 'network';

  /// Rule set format: `binary` or `source`.
  static const String format = 'format';

  /// Path of a local rule set.
  static const String ruleSetPath = 'path';

  // ── experimental (option/experimental.go) ─────────────────────────────

  /// Cache file block.
  static const String cacheFile = 'cache_file';

  /// Whether the FakeIP map survives a restart.
  static const String storeFakeIp = 'store_fakeip';

  /// Clash API block.
  static const String clashApi = 'clash_api';

  /// Address the Clash API listens on.
  static const String externalController = 'external_controller';

  /// Bearer token the Clash API requires.
  static const String secret = 'secret';

  // ── values ────────────────────────────────────────────────────────────

  /// `type` of the TUN inbound.
  static const String typeTun = 'tun';

  /// `type` of the local SOCKS + HTTP inbound.
  static const String typeMixed = 'mixed';

  /// `type` of the direct outbound.
  static const String typeDirect = 'direct';

  /// `type` of a selector group.
  static const String typeSelector = 'selector';

  /// `type` of a urltest group.
  static const String typeUrlTest = 'urltest';

  /// `type` of a local rule set.
  static const String typeLocal = 'local';

  /// `action` that sends traffic to an outbound. The default when omitted.
  static const String actionRoute = 'route';

  /// `action` that drops traffic. Replaces the legacy `block` outbound.
  static const String actionReject = 'reject';

  /// `action` that answers a DNS query inside the core.
  static const String actionHijackDns = 'hijack-dns';

  /// `action` that reads the protocol off the first packets.
  static const String actionSniff = 'sniff';

  /// Sniffed protocol name of a DNS query.
  static const String protocolDns = 'dns';

  /// Rule set format we ship: the compiled one.
  static const String formatBinary = 'binary';
}
