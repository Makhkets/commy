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
    final flow = node.param(ParamKeys.flow);
    if (flow != null && flow.isNotEmpty) {
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
    final options = _head(node, tag)
      ..[SingBoxKeys.method] = _require(node, ParamKeys.method, 'cipher')
      ..[SingBoxKeys.password] = _require(node, ParamKeys.password, 'password');
    final plugin = node.param(ParamKeys.plugin);
    if (plugin != null && plugin.isNotEmpty) {
      options[SingBoxKeys.plugin] = plugin;
      final pluginOpts = node.param(ParamKeys.pluginOpts);
      if (pluginOpts != null && pluginOpts.isNotEmpty) {
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
      options[SingBoxKeys.serverPorts] = <String>[
        for (final range in ports.split(','))
          if (range.trim().isNotEmpty) normalisePortRange(range),
      ];
    }
    final obfs = node.param(ParamKeys.obfs);
    if (obfs != null && obfs.isNotEmpty) {
      final obfsPassword = node.param(ParamKeys.obfsPassword);
      options[SingBoxKeys.obfs] = <String, Object?>{
        SingBoxKeys.type: obfs,
        if (obfsPassword != null && obfsPassword.isNotEmpty)
          SingBoxKeys.password: obfsPassword,
      };
    }
    // Hysteria 2 rides on QUIC: there is no plaintext mode to fall back to.
    options[SingBoxKeys.tls] = TlsOptionsBuilder.build(node, alwaysOn: true);
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
    options[SingBoxKeys.tls] = TlsOptionsBuilder.build(node, alwaysOn: true);
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
    final addresses = _splitList(node.param(ParamKeys.localAddress));
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

  static void _attachTlsAndTransport(
    Map<String, Object?> options,
    ProxyNode node,
  ) {
    final tls = TlsOptionsBuilder.build(node);
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
