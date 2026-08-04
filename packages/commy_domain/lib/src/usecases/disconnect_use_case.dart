import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/ports/core_client.dart';

/// Takes the tunnel down.
class DisconnectUseCase {
  /// Creates the use case.
  const DisconnectUseCase({required this.core});

  /// The core.
  final CoreClient core;

  /// Stops the core. Succeeds when the tunnel was not running either.
  Future<Result<void, CommyFailure>> call() async {
    try {
      await core.stop();
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error, stackTrace) {
      return Err<void, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
