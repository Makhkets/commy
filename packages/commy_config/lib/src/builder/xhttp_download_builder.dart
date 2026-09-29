import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/tls_options_builder.dart';
import 'package:commy_config/src/builder/transport_options_builder.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_config/src/internal/host_port.dart';
import 'package:commy_config/src/internal/link_format_exception.dart';
import 'package:commy_config/src/internal/map_read.dart';
import 'package:commy_config/src/internal/node_factory.dart';
import 'package:commy_config/src/internal/xhttp_settings.dart';
import 'package:commy_config/src/parsers/xray_stream_reader.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `download` block of an XHTTP transport: the second route
/// Xray's `downloadSettings` describes, as `config.Download` in
/// core/xhttp/config reads it.
///
/// Xray parses a `downloadSettings` with the parser of a whole
/// `streamSettings`, and dials it as a server of its own: its own address,
/// TLS or REALITY, HTTP version, host, path, headers and padding; nothing is
/// inherited from the main route but the session id (see core/xhttp/doc.go).
/// So the route is read here the way an Xray outbound is read, into a node of
/// its own, and built by the builders every node goes through — the TLS
/// block of that node is the route's `tls`, the XHTTP settings of that node
/// its options.
///
/// What Xray would refuse, or crash on, is refused here, by the rule it
/// breaks. Two leniencies, both read as no route at all (see [build]): an
/// empty address, and a main route in stream-one.
abstract final class XhttpDownloadBuilder {
  /// Builds the block for [downloadSettings], or returns `null` when it
  /// describes no route.
  ///
  /// [mainPort] is where the route goes when it names no port, as Clash.Meta
  /// does it; [mainMode] is the mode of the main route, which alone decides
  /// the mode of both.
  ///
  /// Throws [ConfigBuildException] naming the first rule the route breaks.
  static Map<String, Object?>? build(
    Object? downloadSettings, {
    required int mainPort,
    required String mainMode,
  }) {
    if (downloadSettings is! Map) {
      return null;
    }
    final route = <String, Object?>{
      for (final entry in downloadSettings.entries) '${entry.key}': entry.value,
    };

    // Xray's own template for this (discussion #4113) ships with
    // `"address": ""`, and Xray dereferences the missing address on the first
    // dial and crashes. A template left unfilled means no second route; both
    // directions then take the main one.
    final rawAddress = MapRead.text(route, const <String>['address']);
    if (rawAddress == null) {
      return null;
    }

    // One request carries both directions in stream-one, so there is no GET
    // to send elsewhere. Xray and mihomo refuse the pair; sing-box-extended,
    // and Commy before it had a second route, ignore the route and connect
    // over the main one. That is kept: a refusal would take a server that
    // works away and protect nothing.
    if (mainMode == XhttpSettings.modeStreamOne) {
      return null;
    }

    var address = rawAddress.toLowerCase();
    if (address.startsWith('[') && address.endsWith(']')) {
      address = address.substring(1, address.length - 1);
    }
    if (!HostPort.isPlausibleHost(address) ||
        PanelNotice.isUnspecified(address)) {
      throw const ConfigBuildException(
        'XHTTP downloadSettings address is not a server',
      );
    }

    final port = _port(route, mainPort);

    final network =
        (MapRead.text(route, const <String>['method', 'network']) ?? 'xhttp')
            .toLowerCase();
    if (network != 'xhttp' && network != 'splithttp') {
      throw ConfigBuildException(
        'XHTTP downloadSettings must use xhttp, not "$network"',
      );
    }

    final params = <String, Object?>{};
    try {
      XrayStreamReader.readInto(
        params,
        <String, Object?>{
          for (final entry in route.entries)
            if (!_networkKeys.contains(MapRead.normalise(entry.key)))
              entry.key: entry.value,
          'network': 'xhttp',
        },
        downloadRoute: true,
      );
    } on LinkFormatException catch (error) {
      throw ConfigBuildException('XHTTP downloadSettings: ${error.reason}');
    }

    final node = NodeFactory.build(
      protocol: Protocol.vless,
      name: 'download',
      host: address,
      port: port,
      params: params,
    );
    try {
      final tls = TlsOptionsBuilder.build(
        node,
        overQuic: TlsOptionsBuilder.isXhttpOverQuic(node),
      );
      return <String, Object?>{
        SingBoxKeys.server: address,
        SingBoxKeys.serverPort: port,
        if (tls != null) SingBoxKeys.tls: tls,
        ...TransportOptionsBuilder.xhttpRoute(node, download: true),
      };
    } on ConfigBuildException catch (error) {
      throw ConfigBuildException('XHTTP downloadSettings: ${error.reason}');
    }
  }

  static final Set<String> _networkKeys = <String>{
    MapRead.normalise('network'),
    MapRead.normalise('method'),
  };

  /// The route's port: its own, or the main route's when it names none.
  ///
  /// Xray would dial port 0; Clash.Meta takes the main port. The second is
  /// what whoever left the port out meant.
  static int _port(Map<String, Object?> route, int mainPort) {
    final raw = MapRead.value(route, const <String>['port']);
    if (raw == null) {
      return mainPort;
    }
    final port = MapRead.integer(route, const <String>['port']);
    if (port == null || port < 0 || port > 65535) {
      throw ConfigBuildException(
        'XHTTP downloadSettings port "$raw" is not a port',
      );
    }
    return port == 0 ? mainPort : port;
  }
}
