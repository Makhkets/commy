import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/ip_check_result.dart';
import 'package:commy_domain/src/ports/ip_check_probe.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// The external IP check behind the button — exception E-1.
///
/// Reads the endpoint from settings on every call. An empty one means the
/// user never turned the feature on, and the answer is then `Ok(null)` rather
/// than a failure: nothing went wrong, because nothing was asked. That is what
/// lets a caller run it unconditionally after the reachability probe and let
/// the setting decide.
class CheckIpUseCase {
  /// Creates the use case.
  const CheckIpUseCase({required this.probe, required this.settings});

  /// What sends the request.
  final IpCheckProbe probe;

  /// Where the endpoint comes from.
  final SettingsRepository settings;

  /// Asks the configured endpoint, or answers `null` when there is none.
  Future<Result<IpCheckResult?, CommyFailure>> call() async {
    try {
      final settingsResult = await settings.read();
      final settingsFailure = settingsResult.failureOrNull;
      if (settingsFailure != null) {
        return Err<IpCheckResult?, CommyFailure>(settingsFailure);
      }
      final appSettings = settingsResult.valueOrNull ?? AppSettings.defaults;
      if (!appSettings.isIpCheckEnabled) {
        return const Ok<IpCheckResult?, CommyFailure>(null);
      }

      final endpoint = Uri.tryParse(appSettings.ipCheckUrl);
      if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
        // The value itself stays out of the message: it is user input, and a
        // failure code is what reaches the log (rule R3).
        return const Err<IpCheckResult?, CommyFailure>(
          ConfigInvalidFailure('The IP check endpoint is not an absolute URL'),
        );
      }

      final probed = await probe.probe(endpoint);
      final probeFailure = probed.failureOrNull;
      if (probeFailure != null) {
        return Err<IpCheckResult?, CommyFailure>(probeFailure);
      }
      return Ok<IpCheckResult?, CommyFailure>(probed.valueOrNull);
    } on Object catch (error, stackTrace) {
      return Err<IpCheckResult?, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }
}
