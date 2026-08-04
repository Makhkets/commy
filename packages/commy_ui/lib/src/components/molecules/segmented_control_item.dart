import 'package:flutter/widgets.dart';

/// One option inside a `SegmentedControl`.
///
/// Generic over the value it stands for, so a routing mode can be selected
/// directly as a `RoutingMode` and not as a string.
@immutable
class SegmentedControlItem<T> {
  /// Creates a segment.
  const SegmentedControlItem({
    required this.value,
    required this.label,
    this.icon,
  });

  /// The value this segment selects.
  final T value;

  /// Text of the segment. Already translated.
  final String label;

  /// Optional leading Lucide icon.
  final IconData? icon;
}
