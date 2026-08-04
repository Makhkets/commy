/// Parsers for proxy links and subscriptions, plus the sing-box config builder.
///
/// Pure Dart, no codegen, no Flutter. This package is the two ends of the data
/// flow in docs/02-architecture.md: step ② turns whatever the user pasted into
/// domain nodes, and step ⑤ turns the state of the app back into a complete
/// configuration for the core.
///
/// The configuration schema is pinned to **sing-box v1.13.16**, the version in
/// docs/13-libbox-reference.md. Bumping the core is rule R8 territory: a
/// separate change with its own matrix run, not a drive-by edit here.
library;

export 'src/builder/clash_api_options.dart';
export 'src/builder/config_build_result.dart';
export 'src/builder/config_platform.dart';
export 'src/builder/dns_section_builder.dart';
export 'src/builder/inbound_section_builder.dart';
export 'src/builder/outbound_builder.dart';
export 'src/builder/route_matcher.dart';
export 'src/builder/route_section_builder.dart';
export 'src/builder/sing_box_build_request.dart';
export 'src/builder/sing_box_config_builder.dart';
export 'src/builder/sing_box_keys.dart';
export 'src/builder/sing_box_tags.dart';
export 'src/builder/tls_options_builder.dart';
export 'src/builder/transport_options_builder.dart';
export 'src/commy_link_parser.dart';
export 'src/export/config_redactor.dart';
export 'src/export/export_outcome.dart';
export 'src/export/node_link_exporter.dart';
export 'src/export/qr_payload.dart';
export 'src/internal/config_build_exception.dart';
export 'src/internal/lenient_base64.dart';
export 'src/internal/link_format_exception.dart';
export 'src/internal/param_keys.dart';
export 'src/parsers/http_link_parser.dart';
export 'src/parsers/hysteria2_link_parser.dart';
export 'src/parsers/link_parser_registry.dart';
export 'src/parsers/node_link_parser.dart';
export 'src/parsers/shadowsocks_link_parser.dart';
export 'src/parsers/shadowtls_link_parser.dart';
export 'src/parsers/socks_link_parser.dart';
export 'src/parsers/transport_params.dart';
export 'src/parsers/trojan_link_parser.dart';
export 'src/parsers/tuic_link_parser.dart';
export 'src/parsers/vless_link_parser.dart';
export 'src/parsers/vmess_link_parser.dart';
export 'src/parsers/wireguard_link_parser.dart';
export 'src/sing_box_config_generator.dart';
export 'src/subscription/clash_proxy_reader.dart';
export 'src/subscription/clash_yaml_reader.dart';
export 'src/subscription/sing_box_outbound_reader.dart';
export 'src/subscription/subscription_body_reader.dart';
export 'src/subscription/subscription_headers.dart';
export 'src/subscription/subscription_parse_result.dart';
export 'src/subscription/subscription_response_parser.dart';
