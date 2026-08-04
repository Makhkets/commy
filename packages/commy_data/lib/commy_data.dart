/// Storage and I/O for Commy: the database, the keystore, the HTTP client and
/// the repository implementations of the domain ports.
///
/// The shape of this package follows one rule and one ADR:
///
/// * **Rule R2** — credentials, subscription URLs and the generated core
///   configuration go to the platform keystore through `SecretVault`, never
///   into a column. The database holds metadata: names, hosts, ports,
///   latencies, rules, daily totals.
/// * **docs/adr/0007-database-encryption.md** — whole-file encryption is not in
///   1.0, because both SQLCipher shims went end of life. The code path is here
///   (`DatabaseEncryption`) and `openCommyDatabase` reports whether it could be
///   used, so a build with a cipher-capable SQLite gets it and every other
///   build says so out loud instead of pretending.
///
/// Nothing in this package throws across its own boundary: every repository
/// method returns `Result<T, CommyFailure>` (docs/02-architecture.md).
library;

export 'src/database/commy_database.dart';
export 'src/database/database_encryption.dart';
export 'src/database/database_opener.dart';
export 'src/database/setting_keys.dart';
export 'src/database/tables/import_failure_rows.dart';
export 'src/database/tables/node_group_rows.dart';
export 'src/database/tables/node_rows.dart';
export 'src/database/tables/routing_rule_rows.dart';
export 'src/database/tables/setting_rows.dart';
export 'src/database/tables/subscription_rows.dart';
export 'src/database/tables/traffic_daily_rows.dart';
export 'src/http/commy_http_client.dart';
export 'src/http/http_text_response.dart';
export 'src/http/http_transport_error.dart';
export 'src/http/network_failure_mapper.dart';
export 'src/http/proxy_endpoint.dart';
export 'src/http/user_agent.dart';
export 'src/logging/log_redactor.dart';
export 'src/logging/ring_buffer_log_repository.dart';
export 'src/mappers/node_group_mapper.dart';
export 'src/mappers/node_mapper.dart';
export 'src/mappers/routing_rule_mapper.dart';
export 'src/mappers/subscription_mapper.dart';
export 'src/models/stored_import_failure.dart';
export 'src/models/traffic_day.dart';
export 'src/repositories/drift_import_failure_store.dart';
export 'src/repositories/drift_node_repository.dart';
export 'src/repositories/drift_routing_repository.dart';
export 'src/repositories/drift_settings_repository.dart';
export 'src/repositories/drift_subscription_repository.dart';
export 'src/repositories/drift_traffic_history_store.dart';
export 'src/repositories/http_subscription_fetcher.dart';
export 'src/secure/flutter_secure_store.dart';
export 'src/secure/in_memory_secure_store.dart';
export 'src/secure/node_secret_parts.dart';
export 'src/secure/secret_keys.dart';
export 'src/secure/secret_vault.dart';
export 'src/secure/secure_store.dart';
export 'src/util/day_key.dart';
export 'src/util/random_id_generator.dart';
export 'src/util/storage_guard.dart';
