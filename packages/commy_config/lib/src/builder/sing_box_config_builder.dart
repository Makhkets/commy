import 'package:commy_config/src/builder/clash_api_options.dart';
import 'package:commy_config/src/builder/config_build_result.dart';
import 'package:commy_config/src/builder/dns_section_builder.dart';
import 'package:commy_config/src/builder/inbound_section_builder.dart';
import 'package:commy_config/src/builder/left_out_node.dart';
import 'package:commy_config/src/builder/outbound_builder.dart';
import 'package:commy_config/src/builder/route_section_builder.dart';
import 'package:commy_config/src/builder/sing_box_build_request.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_config/src/internal/config_build_exception.dart';
import 'package:commy_domain/commy_domain.dart';

/// Assembles a complete sing-box configuration.
///
/// The invariants from docs/06-data-model.md, and where each one lives:
///
/// * **built whole, never patched** — [build] takes the whole state and
///   returns a whole document;
/// * **validated before the core sees it** — [build] returns `Err` rather
///   than letting the core crash;
/// * **deterministic** — the only entropy is the Clash API secret, and that
///   is injected by the caller;
/// * **the app's own traffic stays out** — `exclude_package` on the TUN
///   inbound;
/// * **DNS does not leave the policy** — `hijack-dns` rules plus two
///   separate resolvers;
/// * **`clash_api` on desktop only** — see `ConfigPlatform.allowsClashApi`.
///
/// Schema source: `option/*.go` at tag **v1.13.16**. The core decodes with
/// `DisallowUnknownFields`, so an invented key is a startup failure, not a
/// no-op — every name comes from `SingBoxKeys`.
class SingBoxConfigBuilder {
  /// Creates a builder.
  const SingBoxConfigBuilder();

  /// Interval a urltest group re-measures at, in the core's own notation.
  static const String autoGroupInterval = '5m';

  /// How much better a member has to be before the group switches, in ms.
  static const int autoGroupTolerance = 50;

  /// Whether a document built for [nodeCount] servers carries the Auto group.
  ///
  /// Public because the app has to draw the same answer: a screen that offers
  /// Auto for a single server offers a group the document does not contain,
  /// and then nothing the user taps can be pointed at. Two conditions, and the
  /// second is the one that is easy to forget — a group of one measures one
  /// server against itself and calls the winner a choice.
  static bool usesAutoGroup({
    required bool autoSelect,
    required int nodeCount,
  }) =>
      autoSelect && nodeCount > 1;

  /// Builds the configuration described by [request].
  Result<ConfigBuildResult, CommyFailure> build(
    SingBoxBuildRequest request,
  ) {
    try {
      return Ok<ConfigBuildResult, CommyFailure>(_build(request));
    } on ConfigBuildException catch (error) {
      return Err<ConfigBuildResult, CommyFailure>(
        ConfigInvalidFailure(error.reason),
      );
    } on Object catch (error, stackTrace) {
      return Err<ConfigBuildResult, CommyFailure>(
        UnknownFailure(error, stackTrace),
      );
    }
  }

  ConfigBuildResult _build(SingBoxBuildRequest request) {
    final selected = _validate(request);
    final warnings = <String>[];
    final leftOut = <LeftOutNode>[];

    final outbounds = <Map<String, Object?>>[];
    final endpoints = <Map<String, Object?>>[];
    final memberTags = <String>[];
    for (final node in request.nodes) {
      final tag = SingBoxTags.forNode(node);
      final Map<String, Object?> built;
      try {
        _checkAddress(node);
        if (memberTags.contains(tag)) {
          throw ConfigBuildException(
            'it shares the identifier "${node.id}" with another server',
          );
        }
        built = OutboundBuilder.build(node: node, tag: tag);
      } on ConfigBuildException catch (error) {
        // The document holds every server the user has, so that switching
        // does not mean reconnecting. That must not turn one bad entry in a
        // subscription into a reason none of the others connects: a server
        // that cannot be expressed is left out and named. The exception is
        // the server the user asked for — there the reason IS the answer.
        // By identity, not by id: a second entry with the selected server's
        // id is a duplicate to leave out, not the server that was asked for.
        if (identical(node, selected)) {
          rethrow;
        }
        leftOut.add(
          LeftOutNode(nodeId: node.id, name: node.name, reason: error.reason),
        );
        continue;
      }
      memberTags.add(tag);
      if (OutboundBuilder.isEndpoint(node.protocol)) {
        endpoints.add(built);
      } else {
        outbounds.add(built);
      }
    }

    final selectedTag = SingBoxTags.forNode(selected);
    final useAuto = usesAutoGroup(
      autoSelect: request.autoSelect,
      // Counted after the loop: a group is made of what was built, and a group
      // of one is no group.
      nodeCount: memberTags.length,
    );
    if (useAuto) {
      outbounds.add(_autoGroup(request, memberTags));
    }
    outbounds
      ..add(<String, Object?>{
        SingBoxKeys.type: SingBoxKeys.typeSelector,
        SingBoxKeys.tag: SingBoxTags.proxyGroup,
        SingBoxKeys.groupOutbounds: <String>[
          if (useAuto) SingBoxTags.autoGroup,
          ...memberTags,
        ],
        SingBoxKeys.groupDefault: useAuto ? SingBoxTags.autoGroup : selectedTag,
      })
      ..add(<String, Object?>{
        SingBoxKeys.type: SingBoxKeys.typeDirect,
        SingBoxKeys.tag: SingBoxTags.direct,
      });

    final route = RouteSectionBuilder.build(
      routing: request.routing,
      platform: request.platform,
      availableRuleSets: _usableRuleSets(request),
      ruleSetDirectory: request.ruleSetDirectory,
      warnings: warnings,
    );

    final document = <String, Object?>{
      SingBoxKeys.log: <String, Object?>{
        SingBoxKeys.level: request.settings.logLevel.wireName,
        SingBoxKeys.timestamp: true,
      },
      SingBoxKeys.dns: DnsSectionBuilder.build(
        dns: request.dns,
        routing: request.routing,
        platform: request.platform,
        availableRuleSets: _usableRuleSets(request),
      ),
      SingBoxKeys.inbounds: InboundSectionBuilder.build(
        settings: request.settings,
        routing: request.routing,
        platform: request.platform,
      ),
      if (endpoints.isNotEmpty) SingBoxKeys.endpoints: endpoints,
      SingBoxKeys.outbounds: outbounds,
      SingBoxKeys.route: route,
      SingBoxKeys.experimental: _experimental(request),
    };

    return ConfigBuildResult(
      config: CoreConfig(document),
      warnings: List<String>.unmodifiable(warnings),
      leftOut: List<LeftOutNode>.unmodifiable(leftOut),
    );
  }

  Map<String, Object?> _autoGroup(
    SingBoxBuildRequest request,
    List<String> memberTags,
  ) {
    final probe = request.settings.latencyProbeUrl;
    return <String, Object?>{
      SingBoxKeys.type: SingBoxKeys.typeUrlTest,
      SingBoxKeys.tag: SingBoxTags.autoGroup,
      SingBoxKeys.groupOutbounds: memberTags,
      if (probe.isNotEmpty) SingBoxKeys.groupUrl: probe,
      SingBoxKeys.groupInterval: autoGroupInterval,
      SingBoxKeys.groupTolerance: autoGroupTolerance,
    };
  }

  Map<String, Object?> _experimental(SingBoxBuildRequest request) {
    final clashApi = request.exposesClashApi
        ? request.clashApi ?? ClashApiOptions.generate()
        : null;
    return <String, Object?>{
      SingBoxKeys.cacheFile: <String, Object?>{
        SingBoxKeys.enabled: true,
        // Without this the FakeIP map is rebuilt on every start and every
        // already-resolved address in the system cache points at nothing.
        if (request.dns.fakeIp) SingBoxKeys.storeFakeIp: true,
      },
      if (clashApi != null) SingBoxKeys.clashApi: clashApi.toJson(),
    };
  }

  Set<String> _usableRuleSets(SingBoxBuildRequest request) =>
      request.ruleSetDirectory == null
          ? const <String>{}
          : request.availableRuleSets;

  ProxyNode _validate(SingBoxBuildRequest request) {
    if (request.nodes.isEmpty) {
      throw const ConfigBuildException('No node to connect through');
    }
    final selected = request.selectedNode;
    if (selected == null) {
      throw const ConfigBuildException(
        'The selected node is not among the nodes to build',
      );
    }
    final port = request.settings.mixedPort;
    if (request.settings.allowLan && (port < 1 || port > 65535)) {
      throw ConfigBuildException(
        'Local inbound port $port is not a port',
      );
    }
    return selected;
  }

  /// Refuses a node whose address the core could not dial.
  void _checkAddress(ProxyNode node) {
    if (node.host.trim().isEmpty) {
      throw ConfigBuildException('Node "${node.name}" has no server address');
    }
    // The backstop for a panel notice. The app keeps these out of every
    // list, so the user cannot pick one — but a stored selection can outlive
    // the panel that changed its mind, and `0.0.0.0` in an outbound is a
    // tunnel that comes up and dials nowhere, which is the failure that is
    // hardest to read from the outside.
    if (PanelNotice.isUnspecified(node.host)) {
      throw ConfigBuildException(
        '"${node.name}" is a message from the panel, not a server: its '
        'address is ${node.host.trim()}',
      );
    }
    if (node.port < 1 || node.port > 65535) {
      throw ConfigBuildException(
        'Node "${node.name}" has port ${node.port}, which is not a port',
      );
    }
  }
}
