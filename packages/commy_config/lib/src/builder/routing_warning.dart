import 'package:commy_config/src/builder/routing_warning_kind.dart';
import 'package:commy_domain/commy_domain.dart';

/// Something the builder left out of the routing, and why — as a fact, not a
/// sentence.
///
/// The builder used to write these as English sentences, and the routing
/// screen showed them as written: under a Russian heading, in a Russian UI,
/// a line nobody translated. The words belong to the app's translations
/// (CLAUDE.md §5), as they do for the DNS builder's `ResolverProblem`;
/// [toString] keeps an English line for the log, which is read by whoever
/// debugs, not by the user.
class RoutingWarning {
  /// Creates a warning.
  const RoutingWarning(
    this.kind,
    this.subject, {
    this.missing = const <String>[],
  });

  /// What it is about.
  final RoutingWarningKind kind;

  /// What it is about in particular: a rule, a rule set tag or a platform,
  /// depending on [kind].
  final String subject;

  /// Rule sets a rule needs and does not have. Empty for every other kind.
  final List<String> missing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoutingWarning &&
          other.kind == kind &&
          other.subject == subject &&
          Structural.listEquals(other.missing, missing);

  @override
  int get hashCode => Object.hash(kind, subject, Structural.listHash(missing));

  /// The line the log gets. Holds no credentials: rules and tags are not
  /// secrets.
  @override
  String toString() => switch (kind) {
        RoutingWarningKind.adBlockListMissing =>
          'Ad blocking is on but the rule set "$subject" is not on disk; '
              'the rule was left out',
        RoutingWarningKind.ruleNotApplicable =>
          'Rule "$subject" does not apply here',
        RoutingWarningKind.ruleSetsMissing =>
          'Rule "$subject" needs ${missing.join(', ')}, which is not on '
              'disk; the rule was left out',
        RoutingWarningKind.perAppUnavailable =>
          'Per-app routing is not available on $subject',
        RoutingWarningKind.perAppIncludeOnly =>
          'Include-only per-app routing is not expressible on $subject; '
              'the list was left out',
      };
}
