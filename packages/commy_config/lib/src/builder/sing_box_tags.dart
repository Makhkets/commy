import 'package:commy_domain/commy_domain.dart';

/// The tags the generated configuration always uses.
///
/// They are part of the contract with the rest of the app, not an internal
/// detail: `SwitchNodeUseCase` calls `core.select('proxy', outboundTag)` and
/// `MeasureLatencyUseCase` takes an `outboundTag`, so both sides have to derive
/// the same string from the same node. That is what [forNode] is for.
abstract final class SingBoxTags {
  /// The selector group every configuration defines.
  ///
  /// Matches `SwitchNodeUseCase.defaultGroupTag`; changing one without the
  /// other breaks switching nodes without a restart.
  static const String proxyGroup = 'proxy';

  /// The latency-ordered group, present only when the user picked Auto.
  static const String autoGroup = 'auto';

  /// The outbound that leaves the machine without a proxy.
  static const String direct = 'direct';

  /// The TUN inbound.
  static const String tunInbound = 'tun-in';

  /// The local SOCKS + HTTP inbound, present only when LAN access is on.
  static const String mixedInbound = 'mixed-in';

  /// The resolver queried through the tunnel.
  static const String dnsRemote = 'dns-remote';

  /// The resolver queried outside the tunnel.
  static const String dnsDirect = 'dns-direct';

  /// The FakeIP resolver, present only when FakeIP is on.
  static const String dnsFake = 'dns-fake';

  /// Prefix of every per-node outbound tag.
  static const String nodePrefix = 'node-';

  /// Prefix of every generated geosite rule set tag.
  static const String geositePrefix = 'geosite-';

  /// Prefix of every generated geoip rule set tag.
  static const String geoipPrefix = 'geoip-';

  /// The outbound tag of [node].
  ///
  /// Derived from the identifier rather than the name: two nodes in a
  /// subscription may well share a display name, and a duplicate tag is a
  /// startup error in the core.
  static String forNode(ProxyNode node) => '$nodePrefix${node.id}';

  /// The rule set tag for `geosite:<name>`.
  static String geosite(String name) => '$geositePrefix${_slug(name)}';

  /// The rule set tag for `geoip:<name>`.
  static String geoip(String name) => '$geoipPrefix${_slug(name)}';

  /// The file name a rule set tag is loaded from.
  static String ruleSetFileName(String tag) => '$tag.srs';

  static String _slug(String name) =>
      name.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9._-]'), '-');
}
