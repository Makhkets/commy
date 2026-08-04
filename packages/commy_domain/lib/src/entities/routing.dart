import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/structural.dart';

/// How traffic is routed as a whole.
enum RoutingMode {
  /// Everything goes through the proxy.
  global(wireName: 'global'),

  /// The rule list decides, with proxy as the final action.
  rules(wireName: 'rules'),

  /// Nothing goes through the proxy. The tunnel stays up.
  direct(wireName: 'direct');

  const RoutingMode({required this.wireName});

  /// Stable key used in storage and in the generated configuration.
  final String wireName;
}

/// What a matched rule does with the traffic.
enum RuleAction {
  /// Send it through the selected outbound.
  proxy(wireName: 'proxy'),

  /// Send it out directly, bypassing the proxy.
  direct(wireName: 'direct'),

  /// Drop it.
  block(wireName: 'block');

  const RuleAction({required this.wireName});

  /// Outbound tag the generated configuration points the rule at.
  final String wireName;
}

/// How the per-app list is interpreted, where the platform supports one.
enum PerAppMode {
  /// The list is ignored; every app uses the tunnel.
  disabled(wireName: 'disabled'),

  /// Only the listed apps use the tunnel.
  include(wireName: 'include'),

  /// Every app except the listed ones uses the tunnel.
  exclude(wireName: 'exclude');

  const PerAppMode({required this.wireName});

  /// Stable key used in storage.
  final String wireName;
}

/// One routing rule. Order matters: the first match wins.
class RoutingRule {
  /// Creates a rule.
  const RoutingRule({
    required this.id,
    required this.matcher,
    required this.action,
    this.sortIndex = 0,
    this.enabled = true,
  });

  /// Restores a rule from the map produced by [toJson].
  factory RoutingRule.fromJson(JsonMap json) => RoutingRule(
        id: JsonRead.string(json, 'id'),
        matcher: JsonRead.string(json, 'matcher'),
        action: RuleAction.values.byName(JsonRead.string(json, 'action')),
        sortIndex: JsonRead.integerOr(json, 'sortIndex', orElse: 0),
        enabled: JsonRead.boolean(json, 'enabled', orElse: true),
      );

  /// Stable identifier.
  final String id;

  /// What the rule matches, in the core's own syntax.
  ///
  /// Examples: `geosite:ru`, `geoip:private`, `domain_suffix:example.com`,
  /// `process_name:curl`. Validation lives in commy_config, not here: the set
  /// of matchers is a property of the core version, not of the domain.
  final String matcher;

  /// What happens to traffic that matches.
  final RuleAction action;

  /// Position in the list. Lower runs first.
  final int sortIndex;

  /// Whether the rule is currently applied.
  final bool enabled;

  /// Returns a copy with the given fields replaced.
  RoutingRule copyWith({
    String? id,
    String? matcher,
    RuleAction? action,
    int? sortIndex,
    bool? enabled,
  }) {
    return RoutingRule(
      id: id ?? this.id,
      matcher: matcher ?? this.matcher,
      action: action ?? this.action,
      sortIndex: sortIndex ?? this.sortIndex,
      enabled: enabled ?? this.enabled,
    );
  }

  /// Serialises the rule.
  JsonMap toJson() => <String, Object?>{
        'id': id,
        'matcher': matcher,
        'action': action.name,
        'sortIndex': sortIndex,
        'enabled': enabled,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutingRule &&
          other.id == id &&
          other.matcher == matcher &&
          other.action == action &&
          other.sortIndex == sortIndex &&
          other.enabled == enabled;

  @override
  int get hashCode => Object.hash(id, matcher, action, sortIndex, enabled);

  @override
  String toString() => 'RoutingRule($matcher -> ${action.name})';
}

/// The whole routing configuration the user controls.
///
/// Rule R6: anything that changes this has to pass the leak checklist in
/// docs/09-security-privacy.md before it ships.
class RoutingPolicy {
  /// Creates a policy.
  const RoutingPolicy({
    this.mode = RoutingMode.rules,
    this.rules = const <RoutingRule>[],
    this.perAppMode = PerAppMode.disabled,
    this.perAppPackages = const <String>[],
    this.bypassLan = true,
    this.blockAds = false,
  });

  /// Restores a policy from the map produced by [toJson].
  factory RoutingPolicy.fromJson(JsonMap json) => RoutingPolicy(
        mode: RoutingMode.values.byName(
          JsonRead.stringOr(json, 'mode', orElse: 'rules'),
        ),
        rules: <RoutingRule>[
          for (final item in JsonRead.objectList(json, 'rules'))
            RoutingRule.fromJson(item),
        ],
        perAppMode: PerAppMode.values.byName(
          JsonRead.stringOr(json, 'perAppMode', orElse: 'disabled'),
        ),
        perAppPackages: JsonRead.stringList(json, 'perAppPackages'),
        bypassLan: JsonRead.boolean(json, 'bypassLan', orElse: true),
        blockAds: JsonRead.boolean(json, 'blockAds', orElse: false),
      );

  /// The default policy: rule based, LAN bypassed, no ad blocking.
  static const RoutingPolicy defaults = RoutingPolicy();

  /// Overall mode.
  final RoutingMode mode;

  /// Ordered rules. Only consulted when [mode] is [RoutingMode.rules].
  final List<RoutingRule> rules;

  /// How [perAppPackages] is interpreted.
  final PerAppMode perAppMode;

  /// Package names on Android, executable paths on desktop.
  final List<String> perAppPackages;

  /// Whether private ranges skip the tunnel.
  final bool bypassLan;

  /// Whether the ad blocking lists are applied.
  ///
  /// Off by default: turning it on is exception E-3 to rule R1 and pulls a
  /// list from a source the user chooses.
  final bool blockAds;

  /// Rules that are actually applied, in the order they run.
  List<RoutingRule> get activeRules =>
      rules.where((rule) => rule.enabled).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  /// Returns a copy with the given fields replaced.
  RoutingPolicy copyWith({
    RoutingMode? mode,
    List<RoutingRule>? rules,
    PerAppMode? perAppMode,
    List<String>? perAppPackages,
    bool? bypassLan,
    bool? blockAds,
  }) {
    return RoutingPolicy(
      mode: mode ?? this.mode,
      rules: rules ?? this.rules,
      perAppMode: perAppMode ?? this.perAppMode,
      perAppPackages: perAppPackages ?? this.perAppPackages,
      bypassLan: bypassLan ?? this.bypassLan,
      blockAds: blockAds ?? this.blockAds,
    );
  }

  /// Serialises the policy.
  JsonMap toJson() => <String, Object?>{
        'mode': mode.name,
        'rules': <JsonMap>[for (final rule in rules) rule.toJson()],
        'perAppMode': perAppMode.name,
        'perAppPackages': perAppPackages,
        'bypassLan': bypassLan,
        'blockAds': blockAds,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutingPolicy &&
          other.mode == mode &&
          Structural.listEquals(other.rules, rules) &&
          other.perAppMode == perAppMode &&
          Structural.listEquals(other.perAppPackages, perAppPackages) &&
          other.bypassLan == bypassLan &&
          other.blockAds == blockAds;

  @override
  int get hashCode => Object.hash(
        mode,
        Structural.listHash(rules),
        perAppMode,
        Structural.listHash(perAppPackages),
        bypassLan,
        blockAds,
      );

  @override
  String toString() =>
      'RoutingPolicy(${mode.name}, ${rules.length} rules, '
      '${perAppMode.name})';
}
