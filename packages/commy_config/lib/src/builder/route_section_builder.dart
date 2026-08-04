import 'package:commy_config/src/builder/config_platform.dart';
import 'package:commy_config/src/builder/route_matcher.dart';
import 'package:commy_config/src/builder/sing_box_keys.dart';
import 'package:commy_config/src/builder/sing_box_tags.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `route` section.
///
/// Rule order is the whole meaning of this section — the first match wins — so
/// it is fixed here rather than assembled ad hoc:
///
/// 1. `sniff`, so later rules can see what the connection actually is;
/// 2. DNS hijack, so no query escapes the policy (rule R6);
/// 3. LAN bypass, when the user asked for it;
/// 4. ad blocking, when the user turned it on and the list is on disk;
/// 5. per-app exclusions, where the platform expresses them as processes;
/// 6. the user's own rules, in their own order.
///
/// `block` is not an outbound here. The legacy `block` outbound still exists at
/// v1.13.16 but the supported spelling is `"action": "reject"`, and the `dns`
/// outbound that older configs pair with it is not registered at all — writing
/// one would fail with "unknown outbound type".
abstract final class RouteSectionBuilder {
  /// Port plain DNS uses.
  static const int dnsPort = 53;

  /// Rule set tag the ad blocking feature looks for.
  static const String adsRuleSetName = 'ads';

  /// Builds the section, appending anything it had to drop to [warnings].
  static Map<String, Object?> build({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required Set<String> availableRuleSets,
    required String? ruleSetDirectory,
    required List<String> warnings,
  }) {
    final usedRuleSets = <String>{};
    final rules = <Map<String, Object?>>[
      <String, Object?>{SingBoxKeys.action: SingBoxKeys.actionSniff},
      <String, Object?>{
        SingBoxKeys.protocol: SingBoxKeys.protocolDns,
        SingBoxKeys.action: SingBoxKeys.actionHijackDns,
      },
      <String, Object?>{
        SingBoxKeys.port: <int>[dnsPort],
        SingBoxKeys.action: SingBoxKeys.actionHijackDns,
      },
    ];

    if (routing.bypassLan) {
      rules.add(<String, Object?>{
        SingBoxKeys.ipIsPrivate: true,
        SingBoxKeys.outbound: SingBoxTags.direct,
      });
    }

    if (routing.blockAds) {
      final tag = SingBoxTags.geosite(adsRuleSetName);
      if (availableRuleSets.contains(tag)) {
        usedRuleSets.add(tag);
        rules.add(<String, Object?>{
          SingBoxKeys.ruleSet: <String>[tag],
          SingBoxKeys.action: SingBoxKeys.actionReject,
        });
      } else {
        warnings.add(
          'Ad blocking is on but the rule set "$tag" is not on disk; the '
          'rule was left out',
        );
      }
    }

    rules.addAll(
      _perAppRules(
        routing: routing,
        platform: platform,
        warnings: warnings,
      ),
    );

    if (routing.mode == RoutingMode.rules) {
      for (final rule in routing.activeRules) {
        final matcher = RouteMatcher.tryParse(rule.matcher, platform: platform);
        if (matcher == null || matcher.isEmpty) {
          warnings.add('Rule "${rule.matcher}" does not apply here');
          continue;
        }
        final missing = matcher.ruleSets.difference(availableRuleSets);
        if (missing.isNotEmpty) {
          warnings.add(
            'Rule "${rule.matcher}" needs ${missing.join(', ')}, which is not '
            'on disk; the rule was left out',
          );
          continue;
        }
        usedRuleSets.addAll(matcher.ruleSets);
        rules.add(<String, Object?>{
          ...matcher.fields,
          ..._action(rule.action),
        });
      }
    }

    final ruleSets = <Map<String, Object?>>[
      for (final tag in usedRuleSets.toList()..sort())
        <String, Object?>{
          SingBoxKeys.type: SingBoxKeys.typeLocal,
          SingBoxKeys.tag: tag,
          SingBoxKeys.format: SingBoxKeys.formatBinary,
          SingBoxKeys.ruleSetPath:
              '$ruleSetDirectory/${SingBoxTags.ruleSetFileName(tag)}',
        },
    ];

    return <String, Object?>{
      SingBoxKeys.rules: rules,
      if (ruleSets.isNotEmpty) SingBoxKeys.ruleSet: ruleSets,
      SingBoxKeys.autoDetectInterface: true,
      // The proxy server's own hostname has to be resolved outside the tunnel:
      // the tunnel is not up yet when that dial happens.
      SingBoxKeys.defaultDomainResolver: <String, Object?>{
        SingBoxKeys.dnsServer: SingBoxTags.dnsDirect,
      },
      SingBoxKeys.finalTag: finalOutbound(routing.mode),
    };
  }

  /// The outbound everything unmatched ends up in.
  static String finalOutbound(RoutingMode mode) => switch (mode) {
        RoutingMode.global => SingBoxTags.proxyGroup,
        RoutingMode.rules => SingBoxTags.proxyGroup,
        RoutingMode.direct => SingBoxTags.direct,
      };

  static Map<String, Object?> _action(RuleAction action) => switch (action) {
        RuleAction.proxy => <String, Object?>{
            SingBoxKeys.outbound: SingBoxTags.proxyGroup,
          },
        RuleAction.direct => <String, Object?>{
            SingBoxKeys.outbound: SingBoxTags.direct,
          },
        RuleAction.block => <String, Object?>{
            SingBoxKeys.action: SingBoxKeys.actionReject,
          },
      };

  static List<Map<String, Object?>> _perAppRules({
    required RoutingPolicy routing,
    required ConfigPlatform platform,
    required List<String> warnings,
  }) {
    if (routing.perAppMode == PerAppMode.disabled ||
        routing.perAppPackages.isEmpty ||
        platform.supportsPackageRules) {
      // Android expresses this on the TUN inbound instead, which is where the
      // core wants it (docs/13-libbox-reference.md, TunOptions).
      return const <Map<String, Object?>>[];
    }
    if (!platform.supportsProcessRules) {
      warnings.add('Per-app routing is not available on ${platform.name}');
      return const <Map<String, Object?>>[];
    }
    final identifiers = <String>[
      for (final item in routing.perAppPackages)
        if (item.trim().isNotEmpty) item.trim(),
    ];
    if (routing.perAppMode == PerAppMode.include) {
      // "Only these apps" would mean flipping the final action, which silently
      // rewrites what every other rule means. Refusing is the honest answer.
      warnings.add(
        'Include-only per-app routing is not expressible on '
        '${platform.name}; the list was left out',
      );
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        SingBoxKeys.processName: identifiers,
        SingBoxKeys.outbound: SingBoxTags.direct,
      },
    ];
  }
}
