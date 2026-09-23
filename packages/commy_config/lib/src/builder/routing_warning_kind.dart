/// What a routing warning is about. The app turns each into a sentence.
enum RoutingWarningKind {
  /// Ad blocking is on and its list is not on disk. The subject is the
  /// list's tag.
  adBlockListMissing,

  /// A rule that does not parse, or means nothing on this platform. The
  /// subject is the rule as the user wrote it.
  ruleNotApplicable,

  /// A rule that names rule sets which are not on disk. The subject is the
  /// rule; the missing tags travel alongside.
  ruleSetsMissing,

  /// Per-app routing, on a platform that has no way to express it. The
  /// subject is the platform.
  perAppUnavailable,

  /// An "only these apps" list, on a platform that can only exclude apps.
  /// The subject is the platform.
  perAppIncludeOnly,
}
