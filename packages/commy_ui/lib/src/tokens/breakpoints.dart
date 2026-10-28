import 'package:commy_ui/src/tokens/layout_size.dart';

/// The two width thresholds that decide the shell.
///
/// Rule R4: screens must not compare against raw numbers. They ask
/// [sizeFor] — or, in practice, `context.layoutSize`.
abstract final class CommyBreakpoints {
  /// Below this width the layout is [CommyLayoutSize.compact], in dp.
  static const double compact = 600;

  /// From this width the layout is [CommyLayoutSize.expanded], in dp.
  static const double expanded = 1000;

  /// Where a laptop becomes a wide screen and the side inset grows from 32 to
  /// 40 — 1440 (docs/04-design-system.md §4).
  static const double wide = 1440;

  /// Classifies a width in logical pixels.
  static CommyLayoutSize sizeFor(double width) {
    if (width < compact) {
      return CommyLayoutSize.compact;
    }
    if (width < expanded) {
      return CommyLayoutSize.medium;
    }
    return CommyLayoutSize.expanded;
  }
}
