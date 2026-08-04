import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Measures the round trip of one node and records the result.
///
/// A timeout is `Ok(null)`, not an error: the node is still there, it just did
/// not answer, and it stays in the list unless the user asked otherwise
/// (docs/05-ux-flows.md, scenario 4).
class MeasureLatencyUseCase {
  /// Creates the use case.
  const MeasureLatencyUseCase({
    required this.core,
    required this.nodes,
    required this.settings,
  });

  /// The core, which does the probing.
  final CoreClient core;

  /// Where the result is recorded.
  final NodeRepository nodes;

  /// Where the probe URL comes from.
  final SettingsRepository settings;

  /// Probes [outboundTag] and stores the result against [nodeId].
  Future<Result<Duration?, CommyFailure>> call({
    required String nodeId,
    required String outboundTag,
  }) async {
    try {
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

      final probe = Uri.tryParse(appSettings.latencyProbeUrl);
      if (probe == null) {
        return const Err<Duration?, CommyFailure>(
          ConfigInvalidFailure('Latency probe URL is not a valid URL'),
        );
      }

      final latency = await core.urlTest(outboundTag, probe);
      final saved = await nodes.updateLatency(
        id: nodeId,
        latency: latency,
        checkedAt: DateTime.now(),
      );
      final saveFailure = saved.failureOrNull;
      if (saveFailure != null) {
        return Err<Duration?, CommyFailure>(saveFailure);
      }
      return Ok<Duration?, CommyFailure>(latency);
    } on Object catch (error, stackTrace) {
      return Err<Duration?, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
