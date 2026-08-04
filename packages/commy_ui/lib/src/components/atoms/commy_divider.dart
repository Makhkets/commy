import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A hairline separator.
///
/// Defaults to `border/subtle`, which is what separates rows inside one card.
/// [isStrong] switches to `border/default`, for the edge between two blocks.
class CommyDivider extends StatelessWidget {
  /// Creates a horizontal divider.
  const CommyDivider({
    this.indent = 0,
    this.endIndent = 0,
    this.isStrong = false,
    super.key,
  });

  /// Inset from the leading edge.
  final double indent;

  /// Inset from the trailing edge.
  final double endIndent;

  /// Whether to use `border/default` instead of `border/subtle`.
  final bool isStrong;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: CommySizes.dividerThickness,
        child: ColoredBox(
          color: isStrong ? colors.borderDefault : colors.borderSubtle,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
