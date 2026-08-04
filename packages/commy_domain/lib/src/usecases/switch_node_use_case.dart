import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Changes the active node inside the running core.
///
/// Deliberately does **not** restart the tunnel: a stop/start would drop every
/// open connection (docs/05-ux-flows.md, scenario 2). It swaps the member of
/// the selector group and remembers the new choice, nothing else.
class SwitchNodeUseCase {
  /// Creates the use case.
  const SwitchNodeUseCase({required this.core, required this.settings});

  /// Tag of the selector group the generated configuration always defines.
  static const String defaultGroupTag = 'proxy';

  /// The core.
  final CoreClient core;

  /// Where the selection is remembered.
  final SettingsRepository settings;

  /// Points the selector at [outboundTag] and remembers [nodeId].
  Future<Result<void, CommyFailure>> call({
    required String nodeId,
    required String outboundTag,
    String groupTag = defaultGroupTag,
  }) async {
    try {
      await core.select(groupTag, outboundTag);
      final saved = await settings.writeSelectedNodeId(nodeId);
      final failure = saved.failureOrNull;
      if (failure != null) {
        return Err<void, CommyFailure>(failure);
      }
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error, stackTrace) {
      return Err<void, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
