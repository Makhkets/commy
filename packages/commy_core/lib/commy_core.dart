/// The single door to the sing-box core, plus the logger the whole app writes
/// through.
///
/// Features depend on the `CoreClient` interface in `commy_domain` and never on
/// anything in here directly, except through `CoreClientFactory` in the
/// composition root. That is what makes a connect flow testable without a
/// tunnel and what keeps five platforms from leaking into feature code
/// (docs/adr/0005-core-ipc.md).
///
/// The protocol the Android implementation speaks is specified in
/// `packages/commy_core/docs/wire-protocol.md`; the Kotlin side must match it
/// exactly, and the constants both sides are built from are exported here.
library;

export 'src/android/android_core_client.dart';
export 'src/clash/clash_api_client.dart';
export 'src/clash/clash_codec.dart';
export 'src/clash/clash_endpoint.dart';
export 'src/core_client_exception.dart';
export 'src/core_client_factory.dart';
export 'src/fake/fake_core_client.dart';
export 'src/fake/fake_core_step.dart';
export 'src/logging/app_logger.dart';
export 'src/logging/log_redaction.dart';
export 'src/wire/connection_info_codec.dart';
export 'src/wire/log_line_codec.dart';
export 'src/wire/proxy_group_codec.dart';
export 'src/wire/select_codec.dart';
export 'src/wire/traffic_sample_codec.dart';
export 'src/wire/tunnel_status_codec.dart';
export 'src/wire/url_test_codec.dart';
export 'src/wire/wire_channels.dart';
export 'src/wire/wire_error_codes.dart';
export 'src/wire/wire_failure_mapper.dart';
export 'src/wire/wire_format_exception.dart';
export 'src/wire/wire_json.dart';
export 'src/wire/wire_keys.dart';
export 'src/wire/wire_methods.dart';
export 'src/wire/wire_states.dart';
