import 'package:commy_config/src/builder/clash_api_options.dart';
import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_domain/commy_domain.dart';

/// Everything `SingBoxConfigBuilder` needs to produce a configuration.
///
/// More than one node can be handed in on purpose. The core switches between
/// members of a selector group without dropping a single connection, which is
/// what `SwitchNodeUseCase` relies on; a configuration built around exactly one
/// node would force a reconnect on every switch.
class SingBoxBuildRequest {
  /// Creates a request.
  const SingBoxBuildRequest({
    required this.nodes,
    required this.selectedNodeId,
    required this.routing,
    required this.dns,
    required this.settings,
    required this.platform,
    this.includeClashApi = false,
    this.clashApi,
    this.autoSelect = false,
    this.ruleSetDirectory,
    this.availableRuleSets = const <String>{},
  });

  /// Creates a request around a single node.
  factory SingBoxBuildRequest.single({
    required ProxyNode node,
    required RoutingPolicy routing,
    required DnsSettings dns,
    required AppSettings settings,
    required ConfigPlatform platform,
    bool includeClashApi = false,
    ClashApiOptions? clashApi,
    String? ruleSetDirectory,
    Set<String> availableRuleSets = const <String>{},
  }) =>
      SingBoxBuildRequest(
        nodes: <ProxyNode>[node],
        selectedNodeId: node.id,
        routing: routing,
        dns: dns,
        settings: settings,
        platform: platform,
        includeClashApi: includeClashApi,
        clashApi: clashApi,
        ruleSetDirectory: ruleSetDirectory,
        availableRuleSets: availableRuleSets,
      );

  /// Every node that becomes a member of the selector group.
  final List<ProxyNode> nodes;

  /// Identifier of the node the selector starts on.
  final String selectedNodeId;

  /// Routing policy.
  final RoutingPolicy routing;

  /// DNS policy.
  final DnsSettings dns;

  /// Application settings.
  final AppSettings settings;

  /// The operating system this configuration is going to run on.
  final ConfigPlatform platform;

  /// Whether the Clash API is exposed.
  ///
  /// Ignored on the platforms whose [ConfigPlatform.allowsClashApi] is false:
  /// on mobile the data comes through libbox and rule R7 leaves no room for a
  /// second server inside the extension.
  final bool includeClashApi;

  /// Clash API settings. Generated when the caller passed none.
  final ClashApiOptions? clashApi;

  /// Whether a latency-ordered group is added and selected by default.
  final bool autoSelect;

  /// Directory the compiled rule sets live in, or `null` when there is none.
  final String? ruleSetDirectory;

  /// Rule set tags actually present in [ruleSetDirectory].
  ///
  /// The builder never guesses: rule sets are downloaded by explicit user
  /// action (exception E-2 to rule R1), so what is on disk is something only
  /// the caller knows. A rule referring to a tag that is not listed here is
  /// dropped with a warning rather than written into a configuration the core
  /// would refuse to start.
  final Set<String> availableRuleSets;

  /// The node [selectedNodeId] points at, or `null`.
  ProxyNode? get selectedNode {
    for (final node in nodes) {
      if (node.id == selectedNodeId) {
        return node;
      }
    }
    return null;
  }

  /// Whether the Clash API is both wanted and allowed here.
  bool get exposesClashApi => includeClashApi && platform.allowsClashApi;

  /// Never prints the nodes: they carry credentials.
  @override
  String toString() =>
      'SingBoxBuildRequest(${nodes.length} nodes, ${platform.name})';
}
