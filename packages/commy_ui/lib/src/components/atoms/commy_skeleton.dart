import 'dart:async';

import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/motion.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// A loading placeholder: a rounded block that breathes.
///
/// Under `MediaQuery.disableAnimations` the sweep stops and a plain
/// `bg/overlay` block is left, which is still a correct loading affordance —
/// the four mandatory screen states include "loading", and a static block
/// satisfies it.
class CommySkeleton extends StatefulWidget {
  /// Creates a skeleton block.
  const CommySkeleton({
    this.width,
    this.height,
    this.borderRadius,
    super.key,
  });

  /// Width. `null` fills the parent.
  final double? width;

  /// Height. Defaults to [CommySizes.skeletonHeight].
  final double? height;

  /// Corner radius. Defaults to `radius/xs`.
  final BorderRadius? borderRadius;

  @override
  State<CommySkeleton> createState() => _CommySkeletonState();
}

class _CommySkeletonState extends State<CommySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CommyMotion.standard.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = widget.borderRadius ?? context.radii.xsAll;
    return SizedBox(
      width: widget.width,
      height: widget.height ?? CommySizes.skeletonHeight,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final tint = Color.lerp(
            CommyColors.transparent,
            colors.accentWash,
            _controller.value,
          )!;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Color.alphaBlend(tint, colors.bgOverlay),
              borderRadius: radius,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}
