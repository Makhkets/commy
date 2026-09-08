/// The domain layer of Commy: entities, ports and use cases.
///
/// Pure Dart. No Flutter, no packages, no codegen (rule R5 and
/// docs/adr/0006-codegen-and-native-layout.md). Everything outside this
/// package depends inwards on it; it depends on nothing.
library;

export 'src/core/failure.dart';
export 'src/core/json_map.dart';
export 'src/core/json_read.dart';
export 'src/core/redaction.dart';
export 'src/core/result.dart';
export 'src/core/sentinel.dart';
export 'src/core/structural.dart';
export 'src/entities/app_settings.dart';
export 'src/entities/connection_info.dart';
export 'src/entities/core_config.dart';
export 'src/entities/dns_settings.dart';
export 'src/entities/import_failure.dart';
export 'src/entities/log_line.dart';
export 'src/entities/node_group.dart';
export 'src/entities/parse_outcome.dart';
export 'src/entities/protocol.dart';
export 'src/entities/proxy_group.dart';
export 'src/entities/proxy_node.dart';
export 'src/entities/routing.dart';
export 'src/entities/subscription.dart';
export 'src/entities/subscription_payload.dart';
export 'src/entities/subscription_sync_result.dart';
export 'src/entities/traffic_sample.dart';
export 'src/entities/tunnel_status.dart';
export 'src/ports/clipboard_port.dart';
export 'src/ports/config_generator.dart';
export 'src/ports/core_client.dart';
export 'src/ports/id_generator.dart';
export 'src/ports/link_parser.dart';
export 'src/ports/log_repository.dart';
export 'src/ports/node_repository.dart';
export 'src/ports/routing_repository.dart';
export 'src/ports/settings_repository.dart';
export 'src/ports/subscription_fetcher.dart';
export 'src/ports/subscription_repository.dart';
export 'src/usecases/add_subscription_use_case.dart';
export 'src/usecases/build_config_use_case.dart';
export 'src/usecases/check_reachability_use_case.dart';
export 'src/usecases/connect_use_case.dart';
export 'src/usecases/disconnect_use_case.dart';
export 'src/usecases/import_links_use_case.dart';
export 'src/usecases/measure_latency_use_case.dart';
export 'src/usecases/reload_use_case.dart';
export 'src/usecases/switch_node_use_case.dart';
export 'src/usecases/update_subscription_use_case.dart';
