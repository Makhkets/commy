import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/core_config.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/routing.dart';
import 'package:commy_domain/src/ports/config_generator.dart';
import 'package:commy_domain/src/ports/node_repository.dart';
import 'package:commy_domain/src/ports/routing_repository.dart';
import 'package:commy_domain/src/ports/settings_repository.dart';

/// Collects node, settings, routing and DNS and builds the configuration whole.
///
/// Shared by `ConnectUseCase` and `ReloadUseCase` so that what a start sends
/// and what a live reload sends can never drift apart: same stores, same
/// generator, same document. Nothing is patched and nothing is cached — the
/// state of the core is derived from the state of the app every time
/// (docs/02-architecture.md, step 5).
class BuildConfigUseCase {
  /// Creates the use case.
  const BuildConfigUseCase({
    required this.nodes,
    required this.settings,
    required this.routing,
    required this.generator,
    required this.includeClashApi,
  });

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

  /// Builds the configuration for the node with id [nodeId].
  Future<Result<CoreConfig, CommyFailure>> call({
    required String nodeId,
  }) async {
    try {
      final nodeResult = await nodes.findById(nodeId);
      final nodeFailure = nodeResult.failureOrNull;
      if (nodeFailure != null) {
        return Err<CoreConfig, CommyFailure>(nodeFailure);
      }
      final node = nodeResult.valueOrNull;
      if (node == null) {
        return const Err<CoreConfig, CommyFailure>(
          ConfigInvalidFailure('Selected node no longer exists'),
        );
      }

      final settingsResult = await settings.read();
      final settingsFailure = settingsResult.failureOrNull;
      if (settingsFailure != null) {
        return Err<CoreConfig, CommyFailure>(settingsFailure);
      }
      final appSettings = settingsResult.valueOrNull ?? AppSettings.defaults;

      final routingResult = await routing.read();
      final routingFailure = routingResult.failureOrNull;
      if (routingFailure != null) {
        return Err<CoreConfig, CommyFailure>(routingFailure);
      }
      final policy = routingResult.valueOrNull ?? RoutingPolicy.defaults;

      final dnsResult = await routing.readDns();
      final dnsFailure = dnsResult.failureOrNull;
      if (dnsFailure != null) {
        return Err<CoreConfig, CommyFailure>(dnsFailure);
      }
      final dns = dnsResult.valueOrNull ?? DnsSettings.defaults;

      final configResult = generator.build(
        node: node,
        routing: policy,
        dns: dns,
        settings: appSettings,
        includeClashApi: includeClashApi,
      );
      final configFailure = configResult.failureOrNull;
      if (configFailure != null) {
        return Err<CoreConfig, CommyFailure>(configFailure);
      }
      final config = configResult.valueOrNull;
      if (config == null) {
        return const Err<CoreConfig, CommyFailure>(
          ConfigInvalidFailure('Config generator produced nothing'),
        );
      }
      return Ok<CoreConfig, CommyFailure>(config);
    } on Object catch (error, stackTrace) {
      return Err<CoreConfig, CommyFailure>(UnknownFailure(error, stackTrace));
    }
  }
}
