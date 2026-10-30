/// Which of the four button roles a `CommyButton` plays.
///
/// There are four and there will not be a fifth: the moment a system grows a
/// "primary but quieter" it has stopped being a system.
enum CommyButtonVariant {
  /// The one action the screen exists for. Ink on light, chalk on dark.
  primary,

  /// A real alternative to the primary action. Tinted: the neutral `fill`
  /// under ink, no border — "Disconnect" beside the route.
  secondary,

  /// A tertiary action that must not pull the eye. Text only.
  ghost,

  /// Destructive and irreversible. The error fill under white.
  danger,
}
