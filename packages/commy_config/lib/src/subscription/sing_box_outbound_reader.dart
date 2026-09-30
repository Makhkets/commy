import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/param_keys.dart';
import 'package:commy_config/src/internal/xhttp_download_settings.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:commy_config/src/parsers/transport_params.dart';
import 'package:commy_config/src/parsers/vless_link_parser.dart';
import 'package:commy_config/src/parsers/xray_stream_reader.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads one outbound out of a sing-box or an Xray/v2rayN document.
///
/// Both call the array `outbounds` and mean completely different things by an
/// element of it (docs/06-data-model.md). sing-box writes a flat object with
/// `type`, `server` and `server_port`; Xray writes `protocol` plus a
/// `settings` object whose shape depends on the protocol, plus a parallel
/// `streamSettings`. [read] tells them apart by which keys are present.
///
/// Outbounds that are not servers — `direct`, `block`, `freedom`,
/// `blackhole`, `dns`, `selector`, `urltest` — are rejected by name so a
/// wholesale import does not turn plumbing into fake servers.
abstract final class SingBoxOutboundReader {
  /// Outbound types that describe plumbing rather than a server.
  static const Set<String> plumbingTypes = <String>{
    'blackhole',
    'block',
    'direct',
    'dns',
    'freedom',
    'loopback',
    'selector',
    'urltest',
  };

  /// Whether [outbound] looks like something this reader can turn into a node.
  static bool looksLikeServer(Map<String, Object?> outbound) {
    final type =
        MapRead.text(outbound, <String>['type', 'protocol'])?.toLowerCase();
    if (type == null || plumbingTypes.contains(type)) {
      return false;
    }
    return Protocol.fromWireName(type) != null ||
        _xrayProtocols.containsKey(type);
  }

  /// Reads [outbound], throwing [LinkFormatException] when it cannot.
  static ProxyNode read(Map<String, Object?> outbound) {
    final rawType =
        MapRead.text(outbound, <String>['type', 'protocol'])?.toLowerCase();
    if (rawType == null) {
      throw const LinkFormatException('Outbound has no type');
    }
    if (plumbingTypes.contains(rawType)) {
      throw LinkFormatException('"$rawType" is not a server');
    }
    final isXray = outbound.containsKey('settings') ||
        outbound.containsKey('streamSettings');
    if (isXray) {
      return _readXray(rawType, outbound);
    }
    return _readNative(rawType, outbound);
  }

  static const Map<String, Protocol> _xrayProtocols = <String, Protocol>{
    'vless': Protocol.vless,
    'vmess': Protocol.vmess,
    'trojan': Protocol.trojan,
    'shadowsocks': Protocol.shadowsocks,
    'socks': Protocol.socks,
    'http': Protocol.http,
  };

  static ProxyNode _readNative(String rawType, Map<String, Object?> outbound) {
    final protocol = Protocol.fromWireName(rawType);
    if (protocol == null) {
      throw LinkFormatException('Outbound type "$rawType" is not supported');
    }
    final host = MapRead.text(outbound, <String>['server']);
    final port = MapRead.integer(outbound, <String>['server_port']);
    if (protocol == Protocol.wireguard) {
      return _readNativeWireguard(outbound);
    }
    if (host == null || !HostPort.isPlausibleHost(host.toLowerCase())) {
      throw const LinkFormatException('Outbound has no server address');
    }
    if (port == null || port < 1 || port > 65535) {
      throw const LinkFormatException('Outbound has no valid server port');
    }

    final params = <String, Object?>{
      ParamKeys.uuid: MapRead.text(outbound, <String>['uuid']),
      ParamKeys.password: MapRead.text(outbound, <String>['password']),
      ParamKeys.username: MapRead.text(outbound, <String>['username']),
      ParamKeys.method: MapRead.text(outbound, <String>['method']),
      ParamKeys.plugin: MapRead.text(outbound, <String>['plugin']),
      ParamKeys.pluginOpts: MapRead.text(outbound, <String>['plugin_opts']),
      ParamKeys.flow: MapRead.text(outbound, <String>['flow']),
      ParamKeys.congestionControl:
          MapRead.text(outbound, <String>['congestion_control']),
      ParamKeys.udpRelayMode:
          MapRead.text(outbound, <String>['udp_relay_mode']),
      ParamKeys.upMbps: MapRead.integer(outbound, <String>['up_mbps']),
      ParamKeys.downMbps: MapRead.integer(outbound, <String>['down_mbps']),
      ParamKeys.serverPorts:
          MapRead.stringList(outbound, <String>['server_ports']).join(','),
    };
    if (protocol == Protocol.vmess) {
      params[ParamKeys.vmessSecurity] =
          MapRead.text(outbound, <String>['security']) ?? 'auto';
      params[ParamKeys.alterId] =
          '${MapRead.integer(outbound, <String>['alter_id']) ?? 0}';
    }
    if (protocol == Protocol.shadowtls || protocol == Protocol.socks) {
      params[ParamKeys.version] = MapRead.text(outbound, <String>['version']);
    }
    final obfs = MapRead.object(outbound, <String>['obfs']);
    if (obfs != null) {
      params[ParamKeys.obfs] = MapRead.text(obfs, <String>['type']);
      params[ParamKeys.obfsPassword] = MapRead.text(obfs, <String>['password']);
    }
    _readNativeTls(params, outbound, protocol);
    _readNativeTransport(params, outbound);

    return NodeFactory.build(
      protocol: protocol,
      name: MapRead.text(outbound, <String>['tag']) ?? '$host:$port',
      host: host.toLowerCase(),
      port: port,
      params: params,
    );
  }

  /// Reads a WireGuard endpoint (sing-box 1.11 and later) or outbound (1.10
  /// and earlier) through its first peer.
  ///
  /// The outbound could leave `peers` out and carry its one peer on itself:
  /// `server`, `server_port`, `peer_public_key`, with the interface addresses
  /// under `local_address`, where the endpoint says `address`.
  static ProxyNode _readNativeWireguard(Map<String, Object?> outbound) {
    final peers = MapRead.objectList(outbound, <String>['peers']);
    final Map<String, Object?> peer;
    if (peers.isNotEmpty) {
      peer = peers.first;
    } else if (MapRead.text(outbound, <String>['server']) != null) {
      peer = <String, Object?>{
        'address': MapRead.value(outbound, <String>['server']),
        'port': MapRead.value(outbound, <String>['server_port']),
        'public_key': MapRead.value(outbound, <String>['peer_public_key']),
        'pre_shared_key': MapRead.value(outbound, <String>['pre_shared_key']),
        'reserved': MapRead.value(outbound, <String>['reserved']),
      };
    } else {
      throw const LinkFormatException('WireGuard endpoint has no peer');
    }
    final host = MapRead.text(peer, <String>['address', 'server']);
    final port = MapRead.integer(peer, <String>['port', 'server_port']);
    if (host == null || !HostPort.isPlausibleHost(host.toLowerCase())) {
      throw const LinkFormatException('WireGuard peer has no address');
    }
    if (port == null || port < 1 || port > 65535) {
      throw const LinkFormatException('WireGuard peer has no valid port');
    }
    final reserved = MapRead.stringList(peer, <String>['reserved']);
    return NodeFactory.build(
      protocol: Protocol.wireguard,
      name: MapRead.text(outbound, <String>['tag']) ?? '$host:$port',
      host: host.toLowerCase(),
      port: port,
      params: <String, Object?>{
        ParamKeys.privateKey: MapRead.text(outbound, <String>['private_key']),
        ParamKeys.peerPublicKey: MapRead.text(peer, <String>['public_key']),
        ParamKeys.preSharedKey: MapRead.text(peer, <String>['pre_shared_key']),
        ParamKeys.localAddress: MapRead.stringList(
          outbound,
          <String>['address', 'local_address'],
        ).join(','),
        ParamKeys.reserved: reserved.isEmpty ? null : reserved.join(','),
        ParamKeys.mtu: MapRead.integer(outbound, <String>['mtu']),
        ParamKeys.keepAlive: MapRead.integer(
          peer,
          <String>['persistent_keepalive_interval'],
        ),
      },
    );
  }

  static void _readNativeTls(
    Map<String, Object?> params,
    Map<String, Object?> outbound,
    Protocol protocol,
  ) {
    final tls = MapRead.object(outbound, <String>['tls']);
    if (tls == null || !(MapRead.boolean(tls, <String>['enabled']) ?? false)) {
      params[ParamKeys.security] = ParamKeys.securityNone;
      return;
    }
    final reality = MapRead.object(tls, <String>['reality']);
    final realityOn = reality != null &&
        (MapRead.boolean(reality, <String>['enabled']) ?? false);
    params[ParamKeys.security] =
        realityOn ? ParamKeys.securityReality : ParamKeys.securityTls;
    params[ParamKeys.sni] = MapRead.text(tls, <String>['server_name']);
    params[ParamKeys.alpn] = _joinOrNull(
      MapRead.stringList(tls, <String>['alpn']),
    );
    params[ParamKeys.allowInsecure] =
        MapRead.boolean(tls, <String>['insecure']) ?? false;
    params[ParamKeys.disableSni] =
        MapRead.boolean(tls, <String>['disable_sni']) ?? false;
    final utls = MapRead.object(tls, <String>['utls']);
    if (utls != null) {
      params[ParamKeys.fingerprint] =
          MapRead.text(utls, <String>['fingerprint']);
    }
    if (realityOn) {
      params[ParamKeys.publicKey] =
          MapRead.text(reality, <String>['public_key']);
      params[ParamKeys.shortId] = MapRead.text(reality, <String>['short_id']);
    }
  }

  static void _readNativeTransport(
    Map<String, Object?> params,
    Map<String, Object?> outbound,
  ) {
    final transport = MapRead.object(outbound, <String>['transport']);
    if (transport == null) {
      params[ParamKeys.transport] = 'tcp';
      return;
    }
    final rawType = MapRead.text(transport, <String>['type']) ?? 'tcp';
    final normalised = TransportParams.normaliseTransport(rawType);
    if (normalised == null || !TransportParams.supported.contains(normalised)) {
      throw LinkFormatException(
        'Transport "$rawType" is not supported by the core',
      );
    }
    params[ParamKeys.transport] = normalised;
    params[ParamKeys.path] = MapRead.text(transport, <String>['path']);
    params[ParamKeys.serviceName] =
        MapRead.text(transport, <String>['service_name']);
    final hosts = MapRead.stringList(transport, <String>['host']);
    if (hosts.isNotEmpty) {
      params[ParamKeys.host] = hosts.join(',');
    }
    final headers = MapRead.object(transport, <String>['headers']);
    if (headers != null) {
      final hostHeader = MapRead.value(headers, <String>['host']);
      final host = hostHeader is List
          ? MapRead.stringList(headers, <String>['host']).join(',')
          : MapRead.text(headers, <String>['host']);
      if (host != null && host.isNotEmpty) {
        params[ParamKeys.host] = host;
      }
    }
    if (normalised == TransportParams.xhttp) {
      // The block our own builder writes, and the one the sing-box forks that
      // carry XHTTP write: Xray's settings in snake_case, flat.
      final settings = XhttpSettings.read(transport);
      final mode = MapRead.text(transport, <String>['mode']);
      final download = MapRead.object(transport, <String>['download']);
      TransportParams.readXhttpInto(
        params,
        mode: mode,
        extra: settings
            .withDownloadSettings(
              download == null ? null : _xrayDownload(download, mode: mode),
            )
            .toExtraJson(),
      );
    }
  }

  /// The second XHTTP route of a sing-box block, as Xray spells it.
  ///
  /// The block is the one our builder writes, and the sing-box-extended fork
  /// before it: the settings of the route, flat, with `server`,
  /// `server_port` and an outbound's `tls` beside them. It is read with the
  /// readers of a whole outbound, and stored in the shape links carry.
  /// Without a server it describes no route and is dropped.
  ///
  /// The fork's route has no mode of its own and is held to the rules of
  /// [mode], the main route's; so it is stored with that mode, which Xray
  /// checks a route's settings by and uses for nothing else.
  static Map<String, Object?>? _xrayDownload(
    Map<String, Object?> download, {
    required String? mode,
  }) {
    final server = MapRead.text(download, <String>['server']);
    if (server == null) {
      return null;
    }
    final params = <String, Object?>{};
    _readNativeTls(params, download, Protocol.vless);
    final settings = XhttpSettings.read(download);
    final hosts = MapRead.stringList(download, <String>['host']);
    params[ParamKeys.host] = hosts.isEmpty ? settings.hostHeader : hosts.first;
    params[ParamKeys.path] = MapRead.text(download, <String>['path']);
    params[ParamKeys.mode] = MapRead.text(download, <String>['mode']) ?? mode;
    params[ParamKeys.extra] = settings.toExtraJson();
    return XhttpDownloadSettings.write(
      address: server,
      port: MapRead.integer(download, <String>['server_port']),
      params: params,
    );
  }

  static ProxyNode _readXray(String rawType, Map<String, Object?> outbound) {
    final protocol = _xrayProtocols[rawType];
    if (protocol == null) {
      throw LinkFormatException(
        'Outbound protocol "$rawType" is not supported',
      );
    }
    final settings = MapRead.object(outbound, <String>['settings']) ??
        const <String, Object?>{};
    final peer = _xrayPeer(protocol, settings);
    final host = MapRead.text(peer, <String>['address']);
    final port = MapRead.integer(peer, <String>['port']);
    if (host == null || !HostPort.isPlausibleHost(host.toLowerCase())) {
      throw const LinkFormatException('Outbound has no server address');
    }
    if (port == null || port < 1 || port > 65535) {
      throw const LinkFormatException('Outbound has no valid server port');
    }

    final params = <String, Object?>{};
    final users = MapRead.objectList(peer, <String>['users']);
    final user = users.isEmpty ? const <String, Object?>{} : users.first;
    switch (protocol) {
      case Protocol.vless:
        params[ParamKeys.uuid] = MapRead.text(user, <String>['id']);
        params[ParamKeys.flow] = MapRead.text(user, <String>['flow']);
        final encryption = MapRead.text(user, <String>['encryption']);
        VlessLinkParser.requireSupportedEncryption(encryption);
        params[ParamKeys.encryption] = encryption;
      case Protocol.vmess:
        params[ParamKeys.uuid] = MapRead.text(user, <String>['id']);
        params[ParamKeys.vmessSecurity] =
            MapRead.text(user, <String>['security']) ?? 'auto';
        params[ParamKeys.alterId] =
            '${MapRead.integer(user, <String>['alterId']) ?? 0}';
      case Protocol.trojan:
        params[ParamKeys.password] = MapRead.text(peer, <String>['password']);
      case Protocol.shadowsocks:
        params[ParamKeys.method] = MapRead.text(peer, <String>['method']);
        params[ParamKeys.password] = MapRead.text(peer, <String>['password']);
      case Protocol.socks:
      case Protocol.http:
        params[ParamKeys.username] = MapRead.text(user, <String>['user']) ??
            MapRead.text(peer, <String>['user']);
        params[ParamKeys.password] = MapRead.text(user, <String>['pass']) ??
            MapRead.text(peer, <String>['pass']);
      case Protocol.hysteria2:
      case Protocol.tuic:
      case Protocol.wireguard:
      case Protocol.shadowtls:
        throw LinkFormatException(
          'Outbound protocol "$rawType" is not supported',
        );
    }
    XrayStreamReader.readInto(
      params,
      MapRead.object(outbound, <String>['streamSettings']) ??
          const <String, Object?>{},
    );

    return NodeFactory.build(
      protocol: protocol,
      name: MapRead.text(outbound, <String>['tag']) ?? '$host:$port',
      host: host.toLowerCase(),
      port: port,
      params: params,
    );
  }

  static Map<String, Object?> _xrayPeer(
    Protocol protocol,
    Map<String, Object?> settings,
  ) {
    final vnext = MapRead.objectList(settings, <String>['vnext']);
    if (vnext.isNotEmpty) {
      return vnext.first;
    }
    final servers = MapRead.objectList(settings, <String>['servers']);
    if (servers.isNotEmpty) {
      return servers.first;
    }
    throw LinkFormatException(
      '${protocol.wireName} outbound has neither vnext nor servers',
    );
  }

  static String? _joinOrNull(List<String> values) =>
      values.isEmpty ? null : values.join(',');
}
