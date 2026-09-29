import 'dart:convert';

import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/tls_options_builder.dart';
import 'package:commy_config/src/builder/transport_options_builder.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Turns one [ProxyNode] into the object the core expects.
///
/// Every field name comes from `SingBoxKeys`, which was read off `option/*.go`
/// at tag v1.13.16. Two structural facts drive the shape of this file:
///
/// * **WireGuard is not an outbound any more.** It was deprecated in 1.11.0
///   and removed in 1.13.0 in favour of a WireGuard *endpoint*, which lives in
///   the top level `endpoints` array. [isEndpoint] says which array a node
///   belongs in.
/// * **Unknown fields are fatal.** `option.Options` decodes with
///   `DisallowUnknownFields`, so anything written here that the core does not
///   know refuses to start rather than being ignored.
abstract final class OutboundBuilder {
  /// Default VMess cipher when the link named none.
  static const String defaultVmessSecurity = 'auto';

  /// Default SOCKS version when the link named none.
  static const String defaultSocksVersion = '5';

  /// Default ShadowTLS version when the link named none.
  static const int defaultShadowtlsVersion = 3;

  /// Prefixes a WireGuard peer carries when the link named none.
  static const List<String> defaultAllowedIps = <String>['0.0.0.0/0', '::/0'];

  /// Congestion controllers TUIC accepts.
  static const Set<String> tuicCongestionControllers = <String>{
    'cubic',
    'new_reno',
    'bbr',
  };

  /// The one VLESS flow the core knows (`sing-vmess/vless/client.go`).
  static const String visionFlow = 'xtls-rprx-vision';

  /// Shadowsocks ciphers the core registers, in `sing-shadowsocks2` v0.2.1:
  /// AEAD, AEAD 2022, the legacy stream ciphers, and none.
  static const Set<String> shadowsocksMethods = <String>{
    'none',
    'aes-128-gcm',
    'aes-192-gcm',
    'aes-256-gcm',
    'chacha20-ietf-poly1305',
    'xchacha20-ietf-poly1305',
    '2022-blake3-aes-128-gcm',
    '2022-blake3-aes-256-gcm',
    '2022-blake3-chacha20-poly1305',
    'aes-128-ctr',
    'aes-192-ctr',
    'aes-256-ctr',
    'aes-128-cfb',
    'aes-192-cfb',
    'aes-256-cfb',
    'rc4-md5',
    'chacha20-ietf',
    'xchacha20',
  };

  /// Other spellings of a cipher in [shadowsocksMethods], as Xray and older
  /// clients write them.
  static const Map<String, String> _shadowsocksAliases = <String, String>{
    'chacha20-poly1305': 'chacha20-ietf-poly1305',
    'xchacha20-poly1305': 'xchacha20-ietf-poly1305',
    'plain': 'none',
  };

  /// SIP003 plugins the core registers (`transport/sip003`).
  static const Set<String> shadowsocksPlugins = <String>{
    'obfs-local',
    'v2ray-plugin',
  };

  /// Whether [protocol] belongs in `endpoints` rather than in `outbounds`.
  static bool isEndpoint(Protocol protocol) => protocol == Protocol.wireguard;

  /// Builds the object for [node] under [tag].
  ///
  /// Throws [ConfigBuildException] when the node is missing something the
  /// protocol cannot start without.
  static Map<String, Object?> build({
    required ProxyNode node,
    required String tag,
  }) =>
      switch (node.protocol) {
        Protocol.vless => _vless(node, tag),
        Protocol.vmess => _vmess(node, tag),
        Protocol.trojan => _trojan(node, tag),
        Protocol.shadowsocks => _shadowsocks(node, tag),
        Protocol.hysteria2 => _hysteria2(node, tag),
        Protocol.tuic => _tuic(node, tag),
        Protocol.wireguard => _wireguard(node, tag),
        Protocol.shadowtls => _shadowtls(node, tag),
        Protocol.socks => _socks(node, tag),
        Protocol.http => _http(node, tag),
      };

  /// Normalises a port hopping range: sing-box writes `start:end`.
  static String normalisePortRange(String raw) =>
      raw.trim().replaceAll('-', ':');

  static Map<String, Object?> _head(ProxyNode node, String tag) =>
      <String, Object?>{
        SingBoxKeys.type: node.protocol.wireName,
        SingBoxKeys.tag: tag,
        SingBoxKeys.server: node.host,
        SingBoxKeys.serverPort: node.port,
      };

  static Map<String, Object?> _vless(ProxyNode node, String tag) {
    final options = _head(node, tag)
      ..[SingBoxKeys.uuid] = _require(node, ParamKeys.uuid, 'user id');
    final flow = _vlessFlow(node);
    if (flow != null) {
      options[SingBoxKeys.flow] = flow;
    }
    // `packet_encoding` is deliberately absent: `protocol/vless/outbound.go`
    // turns xudp on when the field is missing, so writing it adds a way to
    // get it wrong and nothing else.
    _attachTlsAndTransport(options, node);
    return options;
  }

  static Map<String, Object?> _vmess(ProxyNode node, String tag) {
    final options = _head(node, tag)
      ..[SingBoxKeys.uuid] = _require(node, ParamKeys.uuid, 'user id')
      ..[SingBoxKeys.security] =
          node.param(ParamKeys.vmessSecurity) ?? defaultVmessSecurity;
    final alterId = int.tryParse(node.param(ParamKeys.alterId) ?? '');
    if (alterId != null && alterId > 0) {
      options[SingBoxKeys.alterId] = alterId;
    }
    _attachTlsAndTransport(options, node);
    return options;
  }

  static Map<String, Object?> _trojan(ProxyNode node, String tag) {
    final options = _head(node, tag)
      ..[SingBoxKeys.password] = _require(node, ParamKeys.password, 'password');
    _attachTlsAndTransport(options, node);
    return options;
  }

  static Map<String, Object?> _shadowsocks(ProxyNode node, String tag) {
    final method = _shadowsocksMethod(node);
    final password = method == 'none'
        ? node.param(ParamKeys.password) ?? ''
        : _require(node, ParamKeys.password, 'password');
    if (method.startsWith('2022-')) {
      _checkShadowsocks2022Keys(method, password);
    }
    final options = _head(node, tag)
      ..[SingBoxKeys.method] = method
      ..[SingBoxKeys.password] = password;
    final plugin = node.param(ParamKeys.plugin)?.trim().toLowerCase();
    if (plugin != null && plugin.isNotEmpty) {
      final pluginOpts = node.param(ParamKeys.pluginOpts) ?? '';
      final name = _shadowsocksPlugin(plugin, pluginOpts);
      options[SingBoxKeys.plugin] = name;
      if (pluginOpts.isNotEmpty) {
        options[SingBoxKeys.pluginOpts] = pluginOpts;
      }
    }
    return options;
  }

  static Map<String, Object?> _hysteria2(ProxyNode node, String tag) {
    final options = _head(node, tag);
    final password = node.param(ParamKeys.password);
    if (password != null && password.isNotEmpty) {
      options[SingBoxKeys.password] = password;
    }
    final up = int.tryParse(node.param(ParamKeys.upMbps) ?? '');
    if (up != null && up > 0) {
      options[SingBoxKeys.upMbps] = up;
    }
    final down = int.tryParse(node.param(ParamKeys.downMbps) ?? '');
    if (down != null && down > 0) {
      options[SingBoxKeys.downMbps] = down;
    }
    final ports = node.param(ParamKeys.serverPorts);
    if (ports != null && ports.isNotEmpty) {
      final ranges = <String>[
        for (final range in ports.split(','))
          if (range.trim().isNotEmpty) _hopRange(range),
      ];
      if (ranges.isNotEmpty) {
        options[SingBoxKeys.serverPorts] = ranges;
      }
    }
    final obfs = node.param(ParamKeys.obfs)?.trim().toLowerCase();
    if (obfs != null && obfs.isNotEmpty && obfs != 'none') {
      // `protocol/hysteria2/outbound.go` knows one obfuscation and refuses
      // it without a password — at construction, which is the whole core.
      if (obfs != 'salamander') {
        throw ConfigBuildException(
          'Hysteria 2 obfuscation "$obfs" is not one the core supports',
        );
      }
      final obfsPassword = node.param(ParamKeys.obfsPassword);
      if (obfsPassword == null || obfsPassword.isEmpty) {
        throw const ConfigBuildException(
          'Hysteria 2 obfuscation is on but has no password',
        );
      }
      options[SingBoxKeys.obfs] = <String, Object?>{
        SingBoxKeys.type: obfs,
        SingBoxKeys.password: obfsPassword,
      };
    }
    // Hysteria 2 rides on QUIC: there is no plaintext mode to fall back to.
    options[SingBoxKeys.tls] =
        TlsOptionsBuilder.build(node, alwaysOn: true, overQuic: true);
    return options;
  }

  static Map<String, Object?> _tuic(ProxyNode node, String tag) {
    final options = _head(node, tag)
      ..[SingBoxKeys.uuid] = _require(node, ParamKeys.uuid, 'user id');
    final password = node.param(ParamKeys.password);
    if (password != null && password.isNotEmpty) {
      options[SingBoxKeys.password] = password;
    }
    final controller = node.param(ParamKeys.congestionControl)?.toLowerCase();
    if (controller != null && tuicCongestionControllers.contains(controller)) {
      options[SingBoxKeys.congestionControl] = controller;
    }
    final relayMode = node.param(ParamKeys.udpRelayMode);
    if (relayMode == 'native' || relayMode == 'quic') {
      options[SingBoxKeys.udpRelayMode] = relayMode;
    }
    if (_flag(node, ParamKeys.udpOverStream)) {
      options[SingBoxKeys.udpOverStream] = true;
    }
    options[SingBoxKeys.tls] =
        TlsOptionsBuilder.build(node, alwaysOn: true, overQuic: true);
    return options;
  }

  static Map<String, Object?> _shadowtls(ProxyNode node, String tag) {
    final options = _head(node, tag);
    final version = int.tryParse(node.param(ParamKeys.version) ?? '') ??
        defaultShadowtlsVersion;
    options[SingBoxKeys.version] = version;
    final password = node.param(ParamKeys.password);
    if (version != 1 && (password == null || password.isEmpty)) {
      throw const ConfigBuildException(
        'ShadowTLS version 2 and 3 need a password',
      );
    }
    if (password != null && password.isNotEmpty) {
      options[SingBoxKeys.password] = password;
    }
    options[SingBoxKeys.tls] = TlsOptionsBuilder.build(node, alwaysOn: true);
    return options;
  }

  static Map<String, Object?> _socks(ProxyNode node, String tag) {
    final options = _head(node, tag)
      ..[SingBoxKeys.version] =
          node.param(ParamKeys.socksVersion) ?? defaultSocksVersion;
    final username = node.param(ParamKeys.username);
    if (username != null && username.isNotEmpty) {
      options[SingBoxKeys.username] = username;
      options[SingBoxKeys.password] = node.param(ParamKeys.password) ?? '';
    }
    return options;
  }

  static Map<String, Object?> _http(ProxyNode node, String tag) {
    final options = _head(node, tag);
    final username = node.param(ParamKeys.username);
    if (username != null && username.isNotEmpty) {
      options[SingBoxKeys.username] = username;
      options[SingBoxKeys.password] = node.param(ParamKeys.password) ?? '';
    }
    final tls = TlsOptionsBuilder.build(node);
    if (tls != null) {
      options[SingBoxKeys.tls] = tls;
    }
    return options;
  }

  static Map<String, Object?> _wireguard(ProxyNode node, String tag) {
    final addresses = <String>[
      for (final address in _splitList(node.param(ParamKeys.localAddress)))
        _interfacePrefix(address),
    ];
    if (addresses.isEmpty) {
      throw const ConfigBuildException(
        'WireGuard needs at least one local address',
      );
    }
    final peer = <String, Object?>{
      SingBoxKeys.peerAddress: node.host,
      SingBoxKeys.peerPort: node.port,
      SingBoxKeys.publicKey:
          _require(node, ParamKeys.peerPublicKey, 'peer public key'),
      SingBoxKeys.allowedIps: defaultAllowedIps,
    };
    final preSharedKey = node.param(ParamKeys.preSharedKey);
    if (preSharedKey != null && preSharedKey.isNotEmpty) {
      peer[SingBoxKeys.preSharedKey] = preSharedKey;
    }
    final keepAlive = int.tryParse(node.param(ParamKeys.keepAlive) ?? '');
    if (keepAlive != null && keepAlive > 0) {
      peer[SingBoxKeys.persistentKeepalive] = keepAlive;
    }
    final reserved = _splitList(node.param(ParamKeys.reserved));
    if (reserved.isNotEmpty) {
      final bytes = <int>[
        for (final part in reserved) int.tryParse(part) ?? -1,
      ];
      if (bytes.any((value) => value < 0 || value > 255)) {
        throw const ConfigBuildException(
          'WireGuard reserved bytes must be three numbers in 0..255',
        );
      }
      peer[SingBoxKeys.reserved] = bytes;
    }

    final options = <String, Object?>{
      SingBoxKeys.type: node.protocol.wireName,
      SingBoxKeys.tag: tag,
      SingBoxKeys.address: addresses,
      SingBoxKeys.privateKey:
          _require(node, ParamKeys.privateKey, 'private key'),
      SingBoxKeys.peers: <Map<String, Object?>>[peer],
    };
    final mtu = int.tryParse(node.param(ParamKeys.mtu) ?? '');
    if (mtu != null && mtu > 0) {
      options[SingBoxKeys.mtu] = mtu;
    }
    return options;
  }

  /// The flow as the core spells it, or `null` for none.
  ///
  /// `sing-vmess` accepts vision and nothing else, and it refuses at
  /// construction — one server's flow was every server's tunnel. Xray's
  /// `xtls-rprx-vision-udp443` is vision that also lets QUIC through, which
  /// the core's vision does not stop in the first place.
  static String? _vlessFlow(ProxyNode node) {
    final flow = node.param(ParamKeys.flow)?.trim().toLowerCase();
    if (flow == null || flow.isEmpty || flow == 'none') {
      return null;
    }
    if (flow == visionFlow || flow.startsWith('$visionFlow-')) {
      return visionFlow;
    }
    throw ConfigBuildException(
      'VLESS flow "$flow" is not one the core supports',
    );
  }

  static String _shadowsocksMethod(ProxyNode node) {
    final raw = _require(node, ParamKeys.method, 'cipher').trim().toLowerCase();
    final method = _shadowsocksAliases[raw] ?? raw;
    if (!shadowsocksMethods.contains(method)) {
      throw ConfigBuildException(
        'Shadowsocks cipher "$raw" is not one the core supports',
      );
    }
    return method;
  }

  /// The 2022 ciphers take base64 keys of a fixed length, one or more joined
  /// by `:`, and the core decodes them at construction.
  static void _checkShadowsocks2022Keys(String method, String password) {
    final length = method == '2022-blake3-aes-128-gcm' ? 16 : 32;
    final keys = password.split(':');
    if (method == '2022-blake3-chacha20-poly1305' && keys.length > 1) {
      throw const ConfigBuildException(
        'Shadowsocks 2022 with ChaCha20 takes a single key',
      );
    }
    for (final key in keys) {
      List<int> bytes;
      try {
        bytes = base64.decode(key);
      } on FormatException {
        bytes = const <int>[];
      }
      if (bytes.length != length) {
        throw ConfigBuildException(
          'Shadowsocks 2022 needs a base64 key of $length bytes',
        );
      }
    }
  }

  /// The plugin under the name the core registers it by.
  static String _shadowsocksPlugin(String plugin, String options) {
    final name = switch (plugin) {
      'obfs' || 'simple-obfs' => 'obfs-local',
      _ => plugin,
    };
    if (!shadowsocksPlugins.contains(name)) {
      throw ConfigBuildException(
        'Shadowsocks plugin "$plugin" is not one the core supports',
      );
    }
    final args = _pluginArgs(options);
    if (name == 'obfs-local') {
      final mode = args['obfs'];
      if (mode != null && mode != 'http' && mode != 'tls') {
        throw ConfigBuildException('obfs mode "$mode" is not http or tls');
      }
    } else {
      final mode = args['mode'];
      if (mode != null && mode != 'websocket') {
        throw ConfigBuildException(
          'v2ray-plugin mode "$mode" is not one the core supports',
        );
      }
    }
    return name;
  }

  /// SIP003 options: `key=value` pairs separated by `;`, `\` escaping.
  static Map<String, String> _pluginArgs(String raw) {
    final args = <String, String>{};
    final part = StringBuffer();
    void flush() {
      final text = part.toString();
      part.clear();
      if (text.isEmpty) {
        return;
      }
      final equals = text.indexOf('=');
      if (equals < 0) {
        args[text] = '';
      } else {
        args[text.substring(0, equals)] = text.substring(equals + 1);
      }
    }

    for (var index = 0; index < raw.length; index++) {
      final char = raw[index];
      if (char == r'\' && index + 1 < raw.length) {
        part.write(raw[++index]);
      } else if (char == ';') {
        flush();
      } else {
        part.write(char);
      }
    }
    flush();
    return args;
  }

  /// One hop range as `sing-quic` parses it: always `start:end`.
  ///
  /// A single port — `ports=443` in a link, `server_ports: ["443"]` in a
  /// sing-box profile — has no colon, and `hysteria.ParsePorts` calls that a
  /// bad range and stops the core.
  static String _hopRange(String raw) {
    final range = normalisePortRange(raw);
    final parts = range.split(':');
    int? port(String text) {
      final value = int.tryParse(text.trim());
      return value != null && value > 0 && value <= 65535 ? value : null;
    }

    if (parts.length == 1) {
      final single = port(parts.single);
      if (single != null) {
        return '$single:$single';
      }
    } else if (parts.length == 2) {
      final start = port(parts.first);
      final end = port(parts.last);
      if (start != null && end != null && start <= end) {
        return '$start:$end';
      }
    }
    throw ConfigBuildException('Hysteria 2 port range "$raw" is not valid');
  }

  /// A WireGuard interface address as the core decodes it: a prefix.
  ///
  /// `option.WireGuardEndpointOptions.Address` is a list of `netip.Prefix`,
  /// and a bare address fails the JSON decoding of the whole document. A
  /// single host is what a bare address means, so it gets /32 or /128.
  static String _interfacePrefix(String raw) {
    final slash = raw.indexOf('/');
    final address = slash < 0 ? raw : raw.substring(0, slash);
    final isV6 = address.contains(':');
    final width = isV6 ? 128 : 32;
    try {
      isV6 ? Uri.parseIPv6Address(address) : Uri.parseIPv4Address(address);
    } on FormatException {
      throw ConfigBuildException('WireGuard address "$raw" is not an address');
    }
    if (slash < 0) {
      return '$raw/$width';
    }
    final bits = int.tryParse(raw.substring(slash + 1));
    if (bits == null || bits < 0 || bits > width) {
      throw ConfigBuildException('WireGuard address "$raw" is not an address');
    }
    return raw;
  }

  static void _attachTlsAndTransport(
    Map<String, Object?> options,
    ProxyNode node,
  ) {
    final tls = TlsOptionsBuilder.build(
      node,
      overQuic: TlsOptionsBuilder.isXhttpOverQuic(node),
    );
    if (tls != null) {
      options[SingBoxKeys.tls] = tls;
    }
    final transport = TransportOptionsBuilder.build(node);
    if (transport != null) {
      options[SingBoxKeys.transport] = transport;
    }
  }

  static List<String> _splitList(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String>[];
    }
    return <String>[
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static String _require(ProxyNode node, String key, String label) {
    final value = node.param(key);
    if (value == null || value.isEmpty) {
      throw ConfigBuildException(
        '${node.protocol.wireName} node carries no $label',
      );
    }
    return value;
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
