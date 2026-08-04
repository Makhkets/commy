import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `inbounds` array.
///
/// One TUN inbound, always, plus a local mixed inbound when the user asked to
/// share the tunnel with the LAN. There is deliberately no local inbound
/// otherwise: a listening socket nobody asked for is a surface, not a feature.
///
/// The field names are the post-1.12 ones. `inet4_address`, `inet6_address`,
/// `inet4_route_address` and their siblings were merged into
/// [SingBoxKeys.address] and [SingBoxKeys.routeAddress]; the old spellings
/// still decode but no longer apply anything, which is the single most common
/// way a hand-written config silently fails (docs/13-libbox-reference.md).
abstract final class InboundSectionBuilder {
  /// IPv4 prefix of the tunnel interface.
  static const String tunAddressV4 = '172.19.0.1/30';

  /// IPv6 prefix of the tunnel interface.
  static const String tunAddressV6 = 'fdfe:dcba:9876::1/126';

  /// Interface MTU. The core's own default for TUN.
  static const int tunMtu = 9000;

  /// Package the app itself runs under.
  ///
  /// Always excluded from the tunnel on Android: without it the app's own
  /// traffic — subscription refreshes above all — loops back into a tunnel
  /// that may not be up yet (docs/06-data-model.md, generator invariants).
  static const String ownPackageName = 'dev.commy.app';

  /// Listen address of the local inbound when LAN access is on.
  static const String lanListenAddress = '0.0.0.0';

  /// Builds the array.
  static List<Map<String, Object?>> build({
    required AppSettings settings,
    required RoutingPolicy routing,
    required ConfigPlatform platform,
  }) {
    return <Map<String, Object?>>[
      tun(settings: settings, routing: routing, platform: platform),
      if (settings.allowLan) mixed(settings: settings),
    ];
  }

  /// Builds the TUN inbound.
  static Map<String, Object?> tun({
    required AppSettings settings,
    required RoutingPolicy routing,
    required ConfigPlatform platform,
  }) {
    final inbound = <String, Object?>{
      SingBoxKeys.type: SingBoxKeys.typeTun,
      SingBoxKeys.tag: SingBoxTags.tunInbound,
      SingBoxKeys.address: <String>[tunAddressV4, tunAddressV6],
      SingBoxKeys.mtu: tunMtu,
      SingBoxKeys.autoRoute: true,
      // Rule R6: without strict_route an application can bypass the tunnel by
      // binding to the physical interface.
      SingBoxKeys.strictRoute: true,
      SingBoxKeys.stack: platform.resolveStack(settings.tunStack).wireName,
    };
    // No `sniff` here on purpose. The legacy inbound fields were removed in
    // sing-box 1.13.0 and now fail the whole configuration; sniffing is a
    // route rule action instead.

    if (platform.supportsPackageRules) {
      final packages = _packages(routing);
      switch (routing.perAppMode) {
        case PerAppMode.disabled:
          inbound[SingBoxKeys.excludePackage] = <String>[ownPackageName];
        case PerAppMode.include:
          // Our own package must not be in the include list, or the app talks
          // to its subscription through its own tunnel.
          inbound[SingBoxKeys.includePackage] = <String>[
            for (final package in packages)
              if (package != ownPackageName) package,
          ];
        case PerAppMode.exclude:
          inbound[SingBoxKeys.excludePackage] = <String>{
            ownPackageName,
            ...packages,
          }.toList();
      }
    }
    return inbound;
  }

  /// Builds the local SOCKS + HTTP inbound.
  static Map<String, Object?> mixed({required AppSettings settings}) =>
      <String, Object?>{
        SingBoxKeys.type: SingBoxKeys.typeMixed,
        SingBoxKeys.tag: SingBoxTags.mixedInbound,
        SingBoxKeys.listen: lanListenAddress,
        SingBoxKeys.listenPort: settings.mixedPort,
      };

  static List<String> _packages(RoutingPolicy routing) => <String>[
        for (final package in routing.perAppPackages)
          if (package.trim().isNotEmpty) package.trim(),
      ];
}
