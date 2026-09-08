import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/usecases/build_config_use_case.dart';

/// Rebuilds the configuration and hands it to a running core.
///
/// The other half of the rule that the core's state is derived from the app's
/// on every start: a routing, DNS or settings change while the tunnel is up is
/// applied the same way — whole, through [CoreClient.reload]. That call keeps
/// the TUN device, so the gap between the old core and the new one is a pause,
/// not a window in which traffic goes around the tunnel (rule R6). The
/// alternative, stop-then-start, is a disconnect the user did not ask for.
class ReloadUseCase {
  /// Creates the use case.
  const ReloadUseCase({required this.core, required this.builder});

  /// The core.
  final CoreClient core;

  /// The same assembly a connect uses.
  final BuildConfigUseCase builder;

  /// Applies the current stores to the core, keeping [nodeId] selected.
  Future<Result<void, CommyFailure>> call({required String nodeId}) async {
    final built = await builder(nodeId: nodeId);
    final failure = built.failureOrNull;
    if (failure != null) {
      return Err<void, CommyFailure>(failure);
    }
    final config = built.valueOrNull;
    if (config == null) {
      return const Err<void, CommyFailure>(
        ConfigInvalidFailure('Config generator produced nothing'),
      );
    }
    try {
      await core.reload(config);
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error, stackTrace) {
      return Err<void, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
