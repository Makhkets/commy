import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Answers the question "does traffic actually flow?" after connecting.
///
/// This is what the `checking` state is for. A raised tunnel is not working
/// internet: the server may be dead, the quota spent, the ISP in the way. If
/// we showed "connected" and said nothing, the user would blame the app.
///
/// `Ok(null)` means the probe did not come back — the tunnel is up but
/// unreachable. `Err` means the check itself could not run.
class CheckReachabilityUseCase {
  /// Creates the use case.
  const CheckReachabilityUseCase({required this.core, required this.settings});

  /// The core, which does the probing.
  final CoreClient core;

  /// Where the probe URL comes from.
  final SettingsRepository settings;

  /// Probes the outbound tagged [outboundTag] through the live tunnel.
  Future<Result<Duration?, CommyFailure>> call({
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
      return Ok<Duration?, CommyFailure>(latency);
    } on Object catch (error, stackTrace) {
      return Err<Duration?, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
