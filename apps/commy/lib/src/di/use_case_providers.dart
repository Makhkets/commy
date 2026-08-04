/// The use-case layer of the composition root.
///
/// Nothing here holds state; every provider is a pure assembly of ports. A
/// screen watches a use case, calls it, and gets a `Result` back — the
/// `try/catch` boundary is already inside `commy_domain`.
library;

import 'package:commy/src/config/selector_config_generator.dart';
import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Turns app state into a complete sing-box configuration (step 5 of
/// docs/02-architecture.md).
///
/// It hands the builder every stored node, not just the chosen one, so that
/// the running core has a selector group to switch inside.
final configGeneratorProvider = Provider<ConfigGenerator>((ref) {
  return SelectorConfigGenerator(
    platform: ref.watch(configPlatformProvider),
    knownNodes: () => ref.read(nodesProvider).value ?? const <ProxyNode>[],
  );
});

/// Turns pasted text into stored nodes.
final importLinksUseCaseProvider = Provider<ImportLinksUseCase>((ref) {
  return ImportLinksUseCase(
    parser: ref.watch(linkParserProvider),
    nodes: ref.watch(nodeRepositoryProvider),
  );
});

/// Downloads a subscription and stores it with its nodes.
final addSubscriptionUseCaseProvider = Provider<AddSubscriptionUseCase>((ref) {
  return AddSubscriptionUseCase(
    fetcher: ref.watch(subscriptionFetcherProvider),
    parser: ref.watch(linkParserProvider),
    subscriptions: ref.watch(subscriptionRepositoryProvider),
    nodes: ref.watch(nodeRepositoryProvider),
    ids: ref.watch(idGeneratorProvider),
  );
});

/// Refreshes an existing subscription in place.
final updateSubscriptionUseCaseProvider =
    Provider<UpdateSubscriptionUseCase>((ref) {
  return UpdateSubscriptionUseCase(
    fetcher: ref.watch(subscriptionFetcherProvider),
    parser: ref.watch(linkParserProvider),
    subscriptions: ref.watch(subscriptionRepositoryProvider),
    nodes: ref.watch(nodeRepositoryProvider),
  );
});

/// Builds a configuration and starts the tunnel.
final connectUseCaseProvider = Provider<ConnectUseCase>((ref) {
  final platform = ref.watch(configPlatformProvider);
  return ConnectUseCase(
    core: ref.watch(coreClientProvider),
    nodes: ref.watch(nodeRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    routing: ref.watch(routingRepositoryProvider),
    generator: ref.watch(configGeneratorProvider),
    // Rule R7 and docs/adr/0005: the Clash API is a desktop-only debug
    // surface. Asking for it on a phone would spend the tunnel extension's
    // memory budget on an HTTP server nobody can reach.
    includeClashApi: platform.allowsClashApi,
  );
});

/// Stops the tunnel.
final disconnectUseCaseProvider = Provider<DisconnectUseCase>((ref) {
  return DisconnectUseCase(core: ref.watch(coreClientProvider));
});

/// Switches the outbound inside a running core.
///
/// Deliberately not stop-then-start: restarting drops every open connection,
/// and docs/05-ux-flows.md calls that out as the wrong behaviour.
final switchNodeUseCaseProvider = Provider<SwitchNodeUseCase>((ref) {
  return SwitchNodeUseCase(
    core: ref.watch(coreClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

/// Measures one node and stores the result.
final measureLatencyUseCaseProvider = Provider<MeasureLatencyUseCase>((ref) {
  return MeasureLatencyUseCase(
    core: ref.watch(coreClientProvider),
    nodes: ref.watch(nodeRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

/// The `checking` step: a live tunnel is not the same as working internet.
final checkReachabilityUseCaseProvider =
    Provider<CheckReachabilityUseCase>((ref) {
  return CheckReachabilityUseCase(
    core: ref.watch(coreClientProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
});

/// Turns a stored node back into a shareable link.
final nodeLinkExporterProvider = Provider<NodeLinkExporter>(
  (ref) => NodeLinkExporter(),
);
