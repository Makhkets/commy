import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/ports/config_generator.dart';
import 'package:commy_domain/src/ports/core_client.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';
import 'package:commy_domain/src/usecases/build_config_use_case.dart';

/// Brings the tunnel up on a given node.
///
/// Collects node, settings, routing and DNS, builds the configuration whole
/// and hands it to the core. Nothing is patched and nothing is cached: the
/// state of the core is derived from the state of the app on every start.
/// The assembly itself is [BuildConfigUseCase], shared with the live reload
/// so the two can never send different documents for the same stores.
class ConnectUseCase {
  /// Creates the use case.
  const ConnectUseCase({
    required this.core,
    required this.nodes,
    required this.settings,
    required this.routing,
    required this.generator,
    required this.includeClashApi,
  });

  /// The core.
  final CoreClient core;

  /// Where the node comes from.
  final NodeRepository nodes;

  /// Where the application settings come from.
  final SettingsRepository settings;

  /// Where the routing and DNS policies come from.
  final RoutingRepository routing;

  /// What turns all of that into a configuration.
  final ConfigGenerator generator;

  /// Whether the generated configuration exposes the Clash API.
  ///
  /// Desktop only. On mobile the data flows through libbox, and an extra HTTP
  /// server inside a 50 MiB extension is the last thing we need (rule R7).
  final bool includeClashApi;

  /// Connects through the node with id [nodeId].
  Future<Result<void, CommyFailure>> call({required String nodeId}) async {
    final built = await BuildConfigUseCase(
      nodes: nodes,
      settings: settings,
      routing: routing,
      generator: generator,
      includeClashApi: includeClashApi,
    )(nodeId: nodeId);
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
      await core.start(config);
      await settings.writeSelectedNodeId(nodeId);
      return const Ok<void, CommyFailure>(null);
    } on Object catch (error, stackTrace) {
      return Err<void, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
