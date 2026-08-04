import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/app_settings.dart';
import 'package:commy_domain/src/entities/core_config.dart';
import 'package:commy_domain/src/entities/dns_settings.dart';
import 'package:commy_domain/src/entities/proxy_node.dart';
import 'package:commy_domain/src/entities/routing.dart';

/// Turns the state of the app into a complete sing-box configuration.
///
/// Invariants the implementation owes us (docs/06-data-model.md):
/// * built whole on every start, never patched;
/// * validated before it reaches the core — our error reads better than a
///   core crash;
/// * deterministic, byte for byte, or golden tests are impossible;
/// * the app's own traffic stays out of the tunnel;
/// * DNS never leaves the tunnel past the policy;
/// * `clash_api` on desktop only, never inside the iOS extension (rule R7).
abstract interface class ConfigGenerator {
  /// Builds the configuration for [node] under the given policies.
  ///
  /// [includeClashApi] must be `false` on mobile.
  Result<CoreConfig, CommyFailure> build({
    required ProxyNode node,
    required RoutingPolicy routing,
    required DnsSettings dns,
    required AppSettings settings,
    required bool includeClashApi,
  });
}
