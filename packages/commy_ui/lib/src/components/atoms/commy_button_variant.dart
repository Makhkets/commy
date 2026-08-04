/// Which of the four button roles a `CommyButton` plays.
///
/// There are four and there will not be a fifth: the moment a system grows a
/// "primary but quieter" it has stopped being a system.
enum CommyButtonVariant {
  /// The one action the screen exists for. Chalk on dark, ink on light.
  primary,

  /// A real alternative to the primary action. Raised surface plus a border.
  secondary,

  /// A tertiary action that must not pull the eye. No fill, no border.
  ghost,

  /// Destructive and irreversible. Filled with `status/error`.
  danger,
}
