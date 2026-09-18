import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/protocol.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/latency_probe.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Measures the round trip of one node and records the result.
///
/// A timeout is `Ok(null)`, not an error: the node is still there, it just did
/// not answer, and it stays in the list unless the user asked otherwise
/// (docs/05-ux-flows.md, scenario 4).
///
/// There are two ways to measure and the caller says which applies. Through
/// the core, while the tunnel is up: a request through the node's outbound,
/// the number that matters. Directly, while it is down: the time the server
/// takes to accept a TCP connection ([LatencyProbe]). Asking a core that is
/// not running used to be the only way, which made the ping button fail on
/// every press until the user had already picked a server and connected —
/// the one moment the numbers are no longer needed.
class MeasureLatencyUseCase {
  /// Creates the use case.
  const MeasureLatencyUseCase({
    required this.core,
    required this.probe,
    required this.nodes,
    required this.settings,
  });

  /// How long a direct probe waits for the server to accept.
  static const Duration directTimeout = Duration(seconds: 5);

  /// The core, which does the probing while the tunnel is up.
  final CoreClient core;

  /// What does it while the tunnel is down.
  final LatencyProbe probe;

  /// Where the result is recorded.
  final NodeRepository nodes;

  /// Where the probe URL comes from.
  final SettingsRepository settings;

  /// Whether [node] can be timed with the tunnel down.
  ///
  /// Hysteria2, TUIC and WireGuard listen on UDP, and so does anything carried
  /// over a QUIC or KCP transport. Nothing accepts a TCP connection on their
  /// port, so a direct probe would write "did not answer" against a server
  /// that is perfectly well — a false alarm with an offline glyph on it. They
  /// are measured through the core or not at all.
  ///
  /// Exhaustive on purpose: a protocol added later has to be placed on one
  /// side of this line by whoever adds it.
  static bool isDirectlyMeasurable(ProxyNode node) {
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
    return overTcp && !_udpTransports.contains(transport);
  }

  /// The share-link parameter naming the stream transport.
  static const String _transportKey = 'type';

  static const Set<String> _udpTransports = <String>{'quic', 'kcp'};

  /// Measures [node] and stores the result against it.
  ///
  /// [throughCore] is whether the tunnel is up. [outboundTag] is the node's
  /// outbound in the running document and is only read in that case.
  Future<Result<Duration?, CommyFailure>> call({
    required ProxyNode node,
    required String outboundTag,
    required bool throughCore,
  }) async {
    try {
      final Duration? latency;
      if (throughCore) {
        final settingsResult = await settings.read();
        final settingsFailure = settingsResult.failureOrNull;
        if (settingsFailure != null) {
          return Err<Duration?, CommyFailure>(settingsFailure);
        }
        final appSettings = settingsResult.valueOrNull ?? AppSettings.defaults;
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
        latency = await core.urlTest(outboundTag, url);
      } else {
        if (!isDirectlyMeasurable(node)) {
          return const Err<Duration?, CommyFailure>(
            ConfigInvalidFailure(
              'This protocol can only be measured through a running tunnel',
            ),
          );
        }
        latency = await probe.connectTime(
          node.host,
          node.port,
          timeout: directTimeout,
        );
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
}
