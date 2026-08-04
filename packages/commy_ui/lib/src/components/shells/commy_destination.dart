import 'package:flutter/widgets.dart';

/// One entry of the persistent navigation on tablet and desktop.
///
/// There is no mobile counterpart on purpose — see `MobileShell`. Sections
/// only come back into permanent navigation where there is room for them.
@immutable
class CommyDestination {
  /// Creates a destination.
  ///
  /// [label] is already translated; this package owns no strings. It is shown
  /// on desktop and announced on tablet, where the rail is icons only —
  /// an icon with no name is a guessing game.
  const CommyDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  /// Lucide glyph of the destination.
  final IconData icon;

  /// Name of the destination. Already translated.
  final String label;

  /// Glyph used while the destination is the selected one. Defaults to [icon];
  /// the selection is carried by the wash and the text colour anyway.
  final IconData? selectedIcon;

  /// The glyph to draw given whether this destination is selected.
  IconData iconFor({required bool isSelected}) =>
      isSelected ? (selectedIcon ?? icon) : icon;
}
