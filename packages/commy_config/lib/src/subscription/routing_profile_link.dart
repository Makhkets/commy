import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';

/// A routing profile as a link: `commy://routing/<base64url JSON>` — how one
/// person hands another "Russian sites direct, the rest through the server"
/// without either of them typing a rule (D11, docs/07-roadmap.md).
///
/// What travels is the routing and nothing else: mode, rules, LAN bypass and
/// ad blocking. Never the per-app list — package names of one phone mean
/// nothing on another — and never anything about servers.
///
/// ```json
/// {"v":1,"name":"RU direct","mode":"rules","lan":true,"ads":false,
///  "rules":[["geosite:ru","direct"],["geoip:ru","direct"]]}
/// ```
///
/// A link is received from anywhere, so [decode] is strict: a version it does
/// not know, an action it does not know, more than [maxRules] rules or a
/// matcher longer than [maxMatcher] is a refusal. Whether a matcher means
/// anything is left to the config builder, which already drops — and names —
/// a rule it cannot apply.
abstract final class RoutingProfileLink {
  /// The prefix every such link starts with.
  static const String prefix = 'commy://routing/';

  /// Most rules one link may carry.
  static const int maxRules = 500;

  /// Longest matcher accepted.
  static const int maxMatcher = 256;

  /// [profile] as a link.
  static String encode(RoutingProfile profile) {
    final policy = profile.policy;
    final json = <String, Object?>{
      'v': 1,
      'name': profile.name,
      'mode': policy.mode.wireName,
      'lan': policy.bypassLan,
      'ads': policy.blockAds,
      'rules': <List<Object?>>[
        for (final rule in policy.activeRules)
          <Object?>[rule.matcher, rule.action.wireName],
      ],
    };
    final payload =
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    return '$prefix$payload';
  }

  /// Whether [input] is such a link, readable or not.
  static bool matches(String input) =>
      input.trim().toLowerCase().startsWith(prefix);

  /// The profile in [input], with [id] as its id; `null` when it is not a
  /// readable link of this kind.
  static RoutingProfile? decode(String input, {required String id}) {
    final text = input.trim();
    if (!matches(text) || text.length > 64 * 1024) {
      return null;
    }
    var payload = text.substring(prefix.length);
    final hash = payload.indexOf('#');
    if (hash >= 0) {
      payload = payload.substring(0, hash);
    }
    final Object? json;
    try {
      final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
      json = jsonDecode(utf8.decode(base64Url.decode(padded)));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?> || json['v'] != 1) {
      return null;
    }
    final mode = _byWire(RoutingMode.values, json['mode'], (m) => m.wireName);
    final name = json['name'];
    final rawRules = json['rules'] ?? const <Object?>[];
    if (mode == null ||
        name is! String ||
        name.trim().isEmpty ||
        rawRules is! List<Object?> ||
        rawRules.length > maxRules) {
      return null;
    }
    final rules = <RoutingRule>[];
    for (final raw in rawRules) {
      if (raw is! List<Object?> || raw.length != 2) {
        return null;
      }
      final matcher = raw[0];
      final action = _byWire(RuleAction.values, raw[1], (a) => a.wireName);
      if (matcher is! String ||
          matcher.trim().isEmpty ||
          matcher.length > maxMatcher ||
          action == null) {
        return null;
      }
      rules.add(
        RoutingRule(
          id: '$id-${rules.length}',
          matcher: matcher.trim(),
          action: action,
          sortIndex: rules.length,
        ),
      );
    }
    final lan = json['lan'];
    final ads = json['ads'];
    return RoutingProfile(
      id: id,
      name: name.trim(),
      policy: RoutingPolicy(
        mode: mode,
        rules: rules,
        bypassLan: lan is bool ? lan : RoutingPolicy.defaults.bypassLan,
        blockAds: ads is bool && ads,
      ),
    );
  }

  static T? _byWire<T>(
    List<T> values,
    Object? raw,
    String Function(T value) wire,
  ) {
    for (final value in values) {
      if (wire(value) == raw) {
        return value;
      }
    }
    return null;
  }
}
