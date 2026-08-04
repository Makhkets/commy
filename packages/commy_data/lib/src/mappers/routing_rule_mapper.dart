import 'package:commy_data/src/database/commy_database.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:drift/drift.dart';

/// Row ⇄ `RoutingRule`.
abstract final class RoutingRuleMapper {
  /// What an unreadable `action` column decodes to.
  ///
  /// `direct` rather than `proxy`: a rule whose intent was lost must not
  /// silently start sending traffic somewhere. Failing towards "leave it alone"
  /// is the safer half of rule R6.
  static const RuleAction fallbackAction = RuleAction.direct;

  /// Builds a domain rule out of a row.
  static RoutingRule toDomain(RoutingRuleRow row) => RoutingRule(
        id: row.id,
        matcher: row.matcher,
        action: _actionOf(row.action),
        sortIndex: row.sortIndex,
        enabled: row.enabled,
      );

  /// Builds the row half of [rule].
  static RoutingRuleRowsCompanion toCompanion(RoutingRule rule) =>
      RoutingRuleRowsCompanion(
        id: Value<String>(rule.id),
        matcher: Value<String>(rule.matcher),
        action: Value<String>(rule.action.name),
        sortIndex: Value<int>(rule.sortIndex),
        enabled: Value<bool>(rule.enabled),
      );

  static RuleAction _actionOf(String name) {
    for (final action in RuleAction.values) {
      if (action.name == name || action.wireName == name) {
        return action;
      }
    }
    return fallbackAction;
  }
}
