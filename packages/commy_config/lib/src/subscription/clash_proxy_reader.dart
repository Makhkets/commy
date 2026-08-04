import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_domain/commy_domain.dart';

/// Turns one entry of a Clash `proxies:` list into a node.
///
/// Clash and Clash.Meta describe the same servers as the links do, only with
/// different names for everything: `servername` instead of `sni`,
/// `client-fingerprint` instead of `fp`, `skip-cert-verify` instead of
/// `allowInsecure`, and nested option maps instead of a flat query string.
///
/// Types Clash has and we do not — `ssr`, `snell`, `hysteria` v1, `anytls`,
/// `vless-mux` and friends — become an [ImportFailure] naming the type rather
/// than a node that cannot connect.
abstract final class ClashProxyReader {
  /// Clash `type` values mapped onto ours.
  static const Map<String, Protocol> types = <String, Protocol>{
    'vless': Protocol.vless,
    'vmess': Protocol.vmess,
    'trojan': Protocol.trojan,
    'ss': Protocol.shadowsocks,
    'shadowsocks': Protocol.shadowsocks,
    'hysteria2': Protocol.hysteria2,
    'hy2': Protocol.hysteria2,
    'tuic': Protocol.tuic,
    'wireguard': Protocol.wireguard,
    'socks5': Protocol.socks,
    'socks': Protocol.socks,
    'http': Protocol.http,
  };

  /// Clash `network` values mapped onto the transport names we store.
  static const Map<String, String> networks = <String, String>{
    'tcp': 'tcp',
    'ws': 'ws',
    'grpc': 'grpc',
    'h2': 'http',
    'http': 'http',
    'httpupgrade': 'httpupgrade',
    'quic': 'quic',
  };

  /// Reads [proxy], throwing [LinkFormatException] when it cannot.
  static ProxyNode read(Map<String, Object?> proxy) {
    final rawType = MapRead.text(proxy, <String>['type']);
    if (rawType == null) {
      throw const LinkFormatException('Clash proxy has no type');
    }
    final protocol = types[rawType.toLowerCase()];
    if (protocol == null) {
      throw LinkFormatException('Clash proxy type "$rawType" is not supported');
    }
    final host = MapRead.text(proxy, <String>['server']);
    if (host == null || !HostPort.isPlausibleHost(host.toLowerCase())) {
      throw const LinkFormatException('Clash proxy has no server address');
    }
    final port = MapRead.integer(proxy, <String>['port']);
    if (port == null || port < 1 || port > 65535) {
      throw const LinkFormatException('Clash proxy has no valid port');
    }
    final name = MapRead.text(proxy, <String>['name']) ?? '$host:$port';

    return NodeFactory.build(
      protocol: protocol,
      name: name,
      host: host.toLowerCase(),
      port: port,
      params: _params(protocol, proxy),
    );
  }

  /// Renders a Clash `plugin-opts` map into the SIP003 argument string.
  static String pluginOptions(String plugin, Map<String, Object?> options) {
    final parts = <String>[];
    if (plugin == 'obfs-local') {
      final mode = MapRead.text(options, <String>['mode']);
      final host = MapRead.text(options, <String>['host']);
      if (mode != null) {
        parts.add('obfs=$mode');
      }
      if (host != null) {
        parts.add('obfs-host=$host');
      }
    } else {
      if (MapRead.boolean(options, <String>['tls']) ?? false) {
        parts.add('tls');
      }
      final mode = MapRead.text(options, <String>['mode']);
      if (mode != null && mode != 'websocket') {
        parts.add('mode=$mode');
      }
      final host = MapRead.text(options, <String>['host']);
      if (host != null) {
        parts.add('host=$host');
      }
      final path = MapRead.text(options, <String>['path']);
      if (path != null) {
        parts.add('path=$path');
      }
    }
    return parts.join(';');
  }

  /// Maps a Clash plugin name onto the one sing-box registers.
  static String normalisePlugin(String raw) {
    final plugin = raw.trim().toLowerCase();
    if (plugin == 'obfs' || plugin == 'simple-obfs' || plugin == 'obfs-local') {
      return 'obfs-local';
    }
    return plugin;
  }

  static Map<String, Object?> _params(
    Protocol protocol,
    Map<String, Object?> proxy,
  ) =>
      switch (protocol) {
        Protocol.vless => <String, Object?>{
            ParamKeys.uuid: _require(proxy, <String>['uuid'], 'uuid'),
            ParamKeys.flow: MapRead.text(proxy, <String>['flow']),
            ..._stream(proxy, defaultSecurity: ParamKeys.securityNone),
          },
        Protocol.vmess => <String, Object?>{
            ParamKeys.uuid: _require(proxy, <String>['uuid'], 'uuid'),
            ParamKeys.alterId:
                '${MapRead.integer(proxy, <String>['alterId']) ?? 0}',
            ParamKeys.vmessSecurity:
                MapRead.text(proxy, <String>['cipher']) ?? 'auto',
            ..._stream(proxy, defaultSecurity: ParamKeys.securityNone),
          },
        Protocol.trojan => <String, Object?>{
            ParamKeys.password:
                _require(proxy, <String>['password'], 'password'),
            ..._stream(proxy, defaultSecurity: ParamKeys.securityTls),
          },
        Protocol.shadowsocks => _shadowsocks(proxy),
        Protocol.hysteria2 => _hysteria2(proxy),
        Protocol.tuic => _tuic(proxy),
        Protocol.wireguard => _wireguard(proxy),
        Protocol.shadowtls => <String, Object?>{
            ParamKeys.password: MapRead.text(proxy, <String>['password']),
            ParamKeys.version: MapRead.text(proxy, <String>['version']) ?? '3',
            ParamKeys.sni: _sni(proxy),
          },
        Protocol.socks || Protocol.http => <String, Object?>{
            ParamKeys.username: MapRead.text(proxy, <String>['username']),
            ParamKeys.password: MapRead.text(proxy, <String>['password']),
            ParamKeys.security:
                (MapRead.boolean(proxy, <String>['tls']) ?? false)
                    ? ParamKeys.securityTls
                    : ParamKeys.securityNone,
            ParamKeys.sni: _sni(proxy),
            ParamKeys.allowInsecure: _insecure(proxy),
          },
      };

  static Map<String, Object?> _shadowsocks(Map<String, Object?> proxy) {
    final params = <String, Object?>{
      ParamKeys.method: _require(proxy, <String>['cipher', 'method'], 'cipher'),
      ParamKeys.password: _require(proxy, <String>['password'], 'password'),
    };
    final plugin = MapRead.text(proxy, <String>['plugin']);
    if (plugin != null) {
      final normalised = normalisePlugin(plugin);
      params[ParamKeys.plugin] = normalised;
      final options = MapRead.object(proxy, <String>['plugin-opts']);
      if (options != null) {
        params[ParamKeys.pluginOpts] = pluginOptions(normalised, options);
      }
    }
    return params;
  }

  static Map<String, Object?> _hysteria2(Map<String, Object?> proxy) {
    final obfs = MapRead.text(proxy, <String>['obfs']);
    return <String, Object?>{
      ParamKeys.password:
          _require(proxy, <String>['password', 'auth'], 'password'),
      ParamKeys.sni: _sni(proxy),
      ParamKeys.alpn: _alpn(proxy),
      ParamKeys.obfs: obfs,
      ParamKeys.obfsPassword:
          MapRead.text(proxy, <String>['obfs-password', 'obfs-param']),
      ParamKeys.upMbps: MapRead.integer(proxy, <String>['up', 'up-mbps']),
      ParamKeys.downMbps: MapRead.integer(proxy, <String>['down', 'down-mbps']),
      ParamKeys.serverPorts: MapRead.text(proxy, <String>['ports']),
      ParamKeys.allowInsecure: _insecure(proxy),
    };
  }

  static Map<String, Object?> _tuic(Map<String, Object?> proxy) {
    return <String, Object?>{
      ParamKeys.uuid: _require(proxy, <String>['uuid'], 'uuid'),
      ParamKeys.password: MapRead.text(proxy, <String>['password']),
      ParamKeys.sni: _sni(proxy),
      ParamKeys.alpn: _alpn(proxy),
      ParamKeys.congestionControl: MapRead.text(
        proxy,
        <String>['congestion-controller', 'congestion-control'],
      ),
      ParamKeys.udpRelayMode: MapRead.text(proxy, <String>['udp-relay-mode']),
      ParamKeys.allowInsecure: _insecure(proxy),
    };
  }

  static Map<String, Object?> _wireguard(Map<String, Object?> proxy) {
    final addresses = <String>[
      ...MapRead.stringList(proxy, <String>['ip']),
      ...MapRead.stringList(proxy, <String>['ipv6']),
    ];
    final reserved = MapRead.stringList(proxy, <String>['reserved']);
    return <String, Object?>{
      ParamKeys.privateKey:
          _require(proxy, <String>['private-key'], 'private key'),
      ParamKeys.peerPublicKey:
          _require(proxy, <String>['public-key'], 'peer public key'),
      ParamKeys.preSharedKey: MapRead.text(proxy, <String>['pre-shared-key']),
      ParamKeys.localAddress:
          addresses.isEmpty ? null : _withMasks(addresses).join(','),
      ParamKeys.reserved: reserved.isEmpty ? null : reserved.join(','),
      ParamKeys.mtu: MapRead.integer(proxy, <String>['mtu']),
      ParamKeys.keepAlive:
          MapRead.integer(proxy, <String>['persistent-keepalive']),
    };
  }

  static Map<String, Object?> _stream(
    Map<String, Object?> proxy, {
    required String defaultSecurity,
  }) {
    final rawNetwork = MapRead.text(proxy, <String>['network']);
    final transport = networks[(rawNetwork ?? 'tcp').toLowerCase()];
    if (transport == null || !TransportParams.supported.contains(transport)) {
      throw LinkFormatException(
        'Transport "$rawNetwork" is not supported by the core',
      );
    }
    final reality = MapRead.object(proxy, <String>['reality-opts']);
    final publicKey =
        reality == null ? null : MapRead.text(reality, <String>['public-key']);
    final security = _security(
      proxy,
      publicKey: publicKey,
      defaultSecurity: defaultSecurity,
    );

    final params = <String, Object?>{
      ParamKeys.transport: transport,
      ParamKeys.security: security,
      ParamKeys.sni: _sni(proxy),
      ParamKeys.alpn: _alpn(proxy),
      ParamKeys.fingerprint: MapRead.text(
        proxy,
        <String>['client-fingerprint', 'fingerprint'],
      ),
      ParamKeys.publicKey: publicKey,
      ParamKeys.shortId:
          reality == null ? null : MapRead.text(reality, <String>['short-id']),
      ParamKeys.allowInsecure: _insecure(proxy),
    };
    _readTransportOptions(params, proxy, transport);
    return params;
  }

  static String _security(
    Map<String, Object?> proxy, {
    required String? publicKey,
    required String defaultSecurity,
  }) {
    if (publicKey != null) {
      return ParamKeys.securityReality;
    }
    final declared = MapRead.boolean(proxy, <String>['tls']);
    if (declared != null) {
      return declared ? ParamKeys.securityTls : ParamKeys.securityNone;
    }
    return defaultSecurity;
  }

  static void _readTransportOptions(
    Map<String, Object?> params,
    Map<String, Object?> proxy,
    String transport,
  ) {
    switch (transport) {
      case 'ws':
        final options = MapRead.object(proxy, <String>['ws-opts']);
        if (options == null) {
          return;
        }
        params[ParamKeys.path] = MapRead.text(options, <String>['path']);
        final headers = MapRead.object(options, <String>['headers']);
        if (headers != null) {
          params[ParamKeys.host] = MapRead.text(headers, <String>['host']);
        }
      case 'grpc':
        final options = MapRead.object(proxy, <String>['grpc-opts']);
        if (options == null) {
          return;
        }
        params[ParamKeys.serviceName] =
            MapRead.text(options, <String>['grpc-service-name']);
      case 'http':
        final options = MapRead.object(proxy, <String>['h2-opts']) ??
            MapRead.object(proxy, <String>['http-opts']);
        if (options == null) {
          return;
        }
        final paths = MapRead.stringList(options, <String>['path']);
        if (paths.isNotEmpty) {
          params[ParamKeys.path] = paths.first;
        }
        final hosts = MapRead.stringList(options, <String>['host']);
        if (hosts.isNotEmpty) {
          params[ParamKeys.host] = hosts.join(',');
        }
      case 'httpupgrade':
        final options = MapRead.object(proxy, <String>['http-upgrade-opts']);
        if (options == null) {
          return;
        }
        params[ParamKeys.path] = MapRead.text(options, <String>['path']);
        params[ParamKeys.host] = MapRead.text(options, <String>['host']);
    }
  }

  static List<String> _withMasks(List<String> addresses) => <String>[
        for (final address in addresses)
          address.contains('/')
              ? address
              : '$address/${address.contains(':') ? 128 : 32}',
      ];

  static String? _sni(Map<String, Object?> proxy) =>
      MapRead.text(proxy, <String>['servername', 'sni', 'peer']);

  static String? _alpn(Map<String, Object?> proxy) {
    final alpn = MapRead.stringList(proxy, <String>['alpn']);
    return alpn.isEmpty ? null : alpn.join(',');
  }

  static bool _insecure(Map<String, Object?> proxy) =>
      MapRead.boolean(proxy, <String>['skip-cert-verify', 'insecure']) ?? false;

  static String _require(
    Map<String, Object?> proxy,
    List<String> keys,
    String label,
  ) {
    final value = MapRead.text(proxy, keys);
    if (value == null) {
      throw LinkFormatException('Clash proxy has no $label');
    }
    return value;
  }
}
