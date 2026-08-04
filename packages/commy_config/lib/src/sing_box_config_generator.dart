import 'package:commy_config/src/builder/clash_api_options.dart';
import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/sing_box_build_request.dart';
import 'package:commy_config/src/builder/sing_box_config_builder.dart';
import 'package:commy_domain/commy_domain.dart';

/// The domain's `ConfigGenerator`, backed by [SingBoxConfigBuilder].
///
/// The port takes one node and no platform, because the domain has no business
/// knowing about either the platform matrix or rule set files. Everything the
/// port does not carry is fixed when this object is constructed, which is the
/// composition root's job.
class SingBoxConfigGenerator implements ConfigGenerator {
  /// Creates a generator for [platform].
  const SingBoxConfigGenerator({
    required this.platform,
    this.builder = const SingBoxConfigBuilder(),
    this.clashApi,
    this.ruleSetDirectory,
    this.availableRuleSets = const <String>{},
  });

  /// The operating system the configuration will run on.
  final ConfigPlatform platform;

  /// The builder that does the work.
  final SingBoxConfigBuilder builder;

  /// Clash API settings, or `null` to draw a fresh secret per configuration.
  final ClashApiOptions? clashApi;

  /// Directory the compiled rule sets live in, or `null`.
  final String? ruleSetDirectory;

  /// Rule set tags actually present on disk.
  final Set<String> availableRuleSets;

  @override
  Result<CoreConfig, CommyFailure> build({
    required ProxyNode node,
    required RoutingPolicy routing,
    required DnsSettings dns,
    required AppSettings settings,
    required bool includeClashApi,
  }) {
    final result = builder.build(
      SingBoxBuildRequest.single(
        node: node,
        routing: routing,
        dns: dns,
        settings: settings,
        platform: platform,
        includeClashApi: includeClashApi,
        clashApi: clashApi,
        ruleSetDirectory: ruleSetDirectory,
        availableRuleSets: availableRuleSets,
      ),
    );
    return result.map((built) => built.config);
  }
}
