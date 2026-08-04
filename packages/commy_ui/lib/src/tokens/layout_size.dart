/// Which of the three layouts a given width belongs to.
///
/// The width thresholds themselves are tokens — see `CommyBreakpoints`.
/// Screens never compare raw numbers (rule R4); they switch on this enum.
enum CommyLayoutSize {
  /// Below the first breakpoint. One column, sheets are bottom sheets.
  compact,

  /// Between the breakpoints. Navigation rail plus a detail pane.
  medium,

  /// Above the second breakpoint. Sidebar, two panes, dialogs not sheets.
  expanded;

  /// Whether this is [CommyLayoutSize.compact].
  bool get isCompact => this == CommyLayoutSize.compact;

  /// Whether this is [CommyLayoutSize.medium].
  bool get isMedium => this == CommyLayoutSize.medium;

  /// Whether this is [CommyLayoutSize.expanded].
  bool get isExpanded => this == CommyLayoutSize.expanded;

  /// Whether a modal should be presented as a dialog rather than a sheet.
  bool get prefersDialog => this == CommyLayoutSize.expanded;
}
