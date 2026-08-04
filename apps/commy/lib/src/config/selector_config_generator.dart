import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds a configuration that contains **every** known server, with the
/// chosen one selected.
///
/// `SingBoxConfigGenerator` from `commy_config` builds a single-node document,
/// which is correct for a one-shot export but wrong for the app: a document
/// with one outbound has nothing to select between, so changing servers would
/// mean restarting the core and dropping every open connection. The selector
/// group has to be there from the first start, before the user has any reason
/// to switch.
///
/// The node list arrives through a supplier rather than a field so the
/// generator can stay a `const`-ish singleton in the provider graph while the
/// list underneath it changes with every import.
class SelectorConfigGenerator implements ConfigGenerator {
  /// Creates the generator.
  const SelectorConfigGenerator({
    required this.platform,
    required this.knownNodes,
    this.builder = const SingBoxConfigBuilder(),
    this.onWarnings,
  });

  /// Which sing-box feature set is allowed on this platform.
  final ConfigPlatform platform;

  /// The newest snapshot of every stored node.
  final List<ProxyNode> Function() knownNodes;

  /// The underlying builder, pinned to sing-box v1.13.16.
  final SingBoxConfigBuilder builder;

  /// Receives everything the builder had to drop to produce a valid document.
  ///
  /// The domain port returns a bare `CoreConfig`, so without this the notes
  /// die here — and they are the only place the user is ever told that the
  /// `geosite:` rule they typed was silently removed because no rule set is on
  /// disk. Reported on every build, including one that dropped nothing, so a
  /// listener can clear a stale warning instead of showing it forever.
  final void Function(List<String> warnings)? onWarnings;

  @override
  Result<CoreConfig, CommyFailure> build({
    required ProxyNode node,
    required RoutingPolicy routing,
    required DnsSettings dns,
    required AppSettings settings,
    required bool includeClashApi,
  }) {
    final result = builder.build(
      SingBoxBuildRequest(
        nodes: _allNodesStartingWith(node),
        selectedNodeId: node.id,
        routing: routing,
        dns: dns,
        settings: settings,
        platform: platform,
        includeClashApi: includeClashApi,
      ),
    );
    return result.map((built) {
      onWarnings?.call(built.warnings);
      return built.config;
    });
  }

  /// The selected node first, then everything else, with no duplicates.
  ///
  /// The chosen node leads so that a build with a stale snapshot — a server
  /// imported a millisecond ago, say — still produces a working document
  /// instead of failing on a selection that is not in the list.
  List<ProxyNode> _allNodesStartingWith(ProxyNode node) {
    final nodes = <ProxyNode>[node];
    for (final other in knownNodes()) {
      if (other.id != node.id) {
        nodes.add(other);
      }
    }
    return nodes;
  }
}
