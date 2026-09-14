/// The repository layer of the composition root.
///
/// Everything here is typed as a **domain port**, never as its Drift or HTTP
/// implementation. That is the seam a widget test overrides: a screen test
/// swaps `nodeRepositoryProvider` for an in-memory list and never opens
/// SQLite.
library;

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servers and their groups.
final nodeRepositoryProvider = Provider<NodeRepository>((ref) {
  return DriftNodeRepository(
    database: ref.watch(databaseProvider),
    secrets: ref.watch(secretVaultProvider),
  );
});

/// Subscriptions. Their URLs are secrets and live in the keystore (rule R2).
final subscriptionRepositoryProvider = Provider<SubscriptionRepository>((ref) {
  return DriftSubscriptionRepository(
    database: ref.watch(databaseProvider),
    secrets: ref.watch(secretVaultProvider),
  );
});

/// Application settings, including the selected node id.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return DriftSettingsRepository(database: ref.watch(databaseProvider));
});

/// Routing policy and DNS.
final routingRepositoryProvider = Provider<RoutingRepository>((ref) {
  return DriftRoutingRepository(database: ref.watch(databaseProvider));
});

/// The geoip and geosite files on disk. Exception E-2.
final ruleSetRepositoryProvider = Provider<RuleSetRepository>((ref) {
  final repository = FileRuleSetRepository(
    client: ref.watch(httpClientProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The in-memory log ring the diagnostics screen reads.
///
/// It is deliberately not persisted: a log that survives a reinstall is a log
/// that outlives the user's intent to keep it.
final logRepositoryProvider = Provider<LogRepository>((ref) {
  final repository = RingBufferLogRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

/// Fetches subscription bodies over HTTP. Only user-entered hosts (rule R1).
final subscriptionFetcherProvider = Provider<SubscriptionFetcher>((ref) {
  final parser = SubscriptionResponseParser();
  return HttpSubscriptionFetcher(
    client: ref.watch(httpClientProvider),
    payloadMapper: (body, headers) =>
        parser.parse(body: body, headers: headers).payload,
  );
});

/// Daily traffic totals: two numbers a day, nothing per connection.
final trafficHistoryRepositoryProvider =
    Provider<TrafficHistoryRepository>((ref) {
  return DriftTrafficHistoryStore(database: ref.watch(databaseProvider));
});

// Not wired here: `DriftImportFailureStore`. It exists in commy_data and
// works, but the import sheet already holds this run's skipped lines in
// memory and no screen asks for older ones. It goes in when one does.
