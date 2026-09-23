import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/ping_method.dart';
import 'package:commy_domain/src/entities/protocol.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/ports/config_generator.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/latency_probe.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Measures the round trip of one node and records the result.
///
/// A timeout is `Ok(null)`, not an error: the node is still there, it just did
/// not answer, and it stays in the list unless the user asked otherwise
/// (docs/05-ux-flows.md, scenario 4).
///
/// How is the user's choice, `AppSettings.pingMethod`, and it no longer
/// depends on whether the tunnel is up:
///
/// * [PingMethod.get] — a GET through the server, by a core instance of its
///   own (`CoreClient.probeOutbounds`). It used to be available only through
///   a running core, which made the honest number the one that arrived after
///   the user had already picked a server and connected; before that the list
///   showed TCP handshakes, and a REALITY server that refuses this client
///   accepts a handshake as fast as one that works.
/// * [PingMethod.tcp] — the handshake itself, directly ([LatencyProbe]).
/// * [PingMethod.icmp] — an echo, directly ([LatencyProbe]).
///
/// "Check" on a connected tunnel is not this: it asks the running core about
/// the outbound traffic actually leaves through (`CheckReachabilityUseCase`).
class MeasureLatencyUseCase {
  /// Creates the use case.
  const MeasureLatencyUseCase({
    required this.core,
    required this.probe,
    required this.nodes,
    required this.settings,
    required this.routing,
    required this.generator,
  });

  /// How long a TCP handshake or an echo is waited for.
  static const Duration directTimeout = Duration(seconds: 5);

  /// How long a GET through a server is waited for.
  ///
  /// Longer than [directTimeout]: it is a handshake with the server — TLS or
  /// REALITY on top of TCP — plus a round trip through it to the probe page,
  /// on whatever network the phone is on.
  static const Duration proxyTimeout = Duration(seconds: 8);

  /// Does the GET, in a core instance of its own.
  final CoreClient core;

  /// Does the TCP handshake and the echo.
  final LatencyProbe probe;

  /// Where the result is recorded.
  final NodeRepository nodes;

  /// Where the method and the probe URL come from.
  final SettingsRepository settings;

  /// Where the direct resolver comes from: a probe resolves server names the
  /// way the tunnel does outside itself.
  final RoutingRepository routing;

  /// Builds the configuration the GET runs on.
  final ConfigGenerator generator;

  /// Whether [node] can be timed by [method].
  ///
  /// Only a TCP handshake needs something of the server — a TCP port — and
  /// only some servers have one; see [acceptsTcp].
  static bool canMeasure(ProxyNode node, PingMethod method) =>
      switch (method) {
        PingMethod.get || PingMethod.icmp => true,
        PingMethod.tcp => acceptsTcp(node),
      };

  /// Whether [node] has a TCP port a handshake can be timed against.
  ///
  /// Hysteria2, TUIC and WireGuard listen on UDP, and so does anything carried
  /// over a QUIC or KCP transport. Nothing accepts a TCP connection on their
  /// port, so a TCP probe would write "did not answer" against a server that
  /// is perfectly well — a false alarm with an offline glyph on it. They are
  /// measured by GET or by echo, or not at all.
  ///
  /// Exhaustive on purpose: a protocol added later has to be placed on one
  /// side of this line by whoever adds it.
  static bool acceptsTcp(ProxyNode node) {
    final overTcp = switch (node.protocol) {
      Protocol.hysteria2 || Protocol.tuic || Protocol.wireguard => false,
      Protocol.vless ||
      Protocol.vmess ||
      Protocol.trojan ||
      Protocol.shadowsocks ||
      Protocol.shadowtls ||
      Protocol.socks ||
      Protocol.http =>
        true,
    };
    final transport = node.param(_transportKey)?.trim().toLowerCase();
    if (transport == _xhttp && _isHttp3Only(node)) {
      // XHTTP is HTTP, and HTTP/3 is QUIC. The TCP port of such a server may
      // well be closed, or belong to something else entirely.
      return false;
    }
    return overTcp && !_udpTransports.contains(transport);
  }

  /// Whether the node's ALPN list is `h3` and nothing else — the one spelling
  /// that makes an XHTTP transport pick HTTP/3. Reality is always HTTP/2.
  static bool _isHttp3Only(ProxyNode node) {
    if (node.param('security')?.trim().toLowerCase() == 'reality') {
      return false;
    }
    final alpn = <String>[
      for (final entry in (node.param('alpn') ?? '').split(','))
        if (entry.trim().isNotEmpty) entry.trim().toLowerCase(),
    ];
    return alpn.length == 1 && alpn.single == 'h3';
  }

  /// The share-link parameter naming the stream transport.
  static const String _transportKey = 'type';

  static const Set<String> _udpTransports = <String>{'quic', 'kcp'};

  static const String _xhttp = 'xhttp';

  /// Measures [node] and stores the result against it.
  ///
  /// [outboundTag] is the node's outbound in the configuration the GET runs
  /// on; only that method reads it.
  Future<Result<Duration?, CommyFailure>> call({
    required ProxyNode node,
    required String outboundTag,
  }) async {
    try {
      final settingsResult = await settings.read();
      final settingsFailure = settingsResult.failureOrNull;
      if (settingsFailure != null) {
        return Err<Duration?, CommyFailure>(settingsFailure);
      }
      final appSettings = settingsResult.valueOrNull ?? AppSettings.defaults;

      final Duration? latency;
      switch (appSettings.pingMethod) {
        case PingMethod.get:
          final measured = await _get(node, outboundTag, appSettings);
          final failure = measured.failureOrNull;
          if (failure != null) {
            return Err<Duration?, CommyFailure>(failure);
          }
          latency = measured.valueOrNull;
        case PingMethod.tcp:
          if (!acceptsTcp(node)) {
            return const Err<Duration?, CommyFailure>(
              ConfigInvalidFailure(
                'This server listens on UDP and cannot be timed by a TCP '
                'handshake',
              ),
            );
          }
          latency = await probe.connectTime(
            node.host,
            node.port,
            timeout: directTimeout,
          );
        case PingMethod.icmp:
          latency = await probe.echoTime(node.host, timeout: directTimeout);
      }

      final saved = await nodes.updateLatency(
        id: node.id,
        latency: latency,
        checkedAt: DateTime.now(),
      );
      final saveFailure = saved.failureOrNull;
      if (saveFailure != null) {
        return Err<Duration?, CommyFailure>(saveFailure);
      }
      return Ok<Duration?, CommyFailure>(latency);
    } on Object catch (error, stackTrace) {
      return Err<Duration?, CommyFailure>(
        CommyFailure.fromCaught(error, stackTrace),
      );
    }
  }

  Future<Result<Duration?, CommyFailure>> _get(
    ProxyNode node,
    String outboundTag,
    AppSettings appSettings,
  ) async {
    if (!appSettings.isLatencyProbeEnabled) {
      return const Err<Duration?, CommyFailure>(
        ConfigInvalidFailure('Latency probe URL is not configured'),
      );
    }
    final url = Uri.tryParse(appSettings.latencyProbeUrl);
    if (url == null) {
      return const Err<Duration?, CommyFailure>(
        ConfigInvalidFailure('Latency probe URL is not a valid URL'),
      );
    }
    final dnsResult = await routing.readDns();
    final dnsFailure = dnsResult.failureOrNull;
    if (dnsFailure != null) {
      return Err<Duration?, CommyFailure>(dnsFailure);
    }
    final built = generator.buildProbe(
      nodes: <ProxyNode>[node],
      dns: dnsResult.valueOrNull ?? DnsSettings.defaults,
    );
    final buildFailure = built.failureOrNull;
    if (buildFailure != null) {
      return Err<Duration?, CommyFailure>(buildFailure);
    }
    final delays = await core.probeOutbounds(
      built.valueOrNull!,
      probe: url,
      timeout: proxyTimeout,
    );
    return Ok<Duration?, CommyFailure>(delays[outboundTag]);
  }
}
