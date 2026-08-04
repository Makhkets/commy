import 'package:commy/src/widgets/failure_view.dart';
import 'package:commy_core/commy_core.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders the three states of an [AsyncValue] that are not content.
///
/// The fourth — empty — is deliberately **not** here: "no data" and "nothing
/// to show yet" are different things, and only the screen knows which of its
/// lists being empty deserves an explanation and which is normal. Screens pass
/// their own empty state inside [builder].
class AsyncSection<T> extends StatelessWidget {
  /// Creates the section.
  const AsyncSection({
    required this.value,
    required this.skeleton,
    required this.builder,
    this.onRetry,
    super.key,
  });

  /// What to render.
  final AsyncValue<T> value;

  /// Shown while the first value is on its way.
  ///
  /// A skeleton, not a centred spinner: docs/05-ux-flows.md asks for the shape
  /// of the answer while the answer loads.
  final Widget skeleton;

  /// Builds the content once there is some.
  final Widget Function(BuildContext context, T value) builder;

  /// Retries whatever produced the failure.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      data: (data) => builder(context, data),
      loading: () => skeleton,
      error: (error, stackTrace) => FailureView(
        failure: CoreClientException.failureOf(error, stackTrace),
        onRetry: onRetry,
      ),
    );
  }
}

/// A stack of grey bars standing in for a list that has not arrived.
class ListSkeleton extends StatelessWidget {
  /// Creates the placeholder.
  const ListSkeleton({this.rows = 4, this.hasHeader = false, super.key});

  /// How many rows to draw.
  final int rows;

  /// Whether to draw a wider bar on top, for a card with a title.
  final bool hasHeader;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Padding(
      padding: EdgeInsets.all(spacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasHeader) ...<Widget>[
            const CommySkeleton(width: _headerWidth),
            SizedBox(height: spacing.s4),
          ],
          for (var index = 0; index < rows; index++) ...<Widget>[
            const _SkeletonRow(),
            SizedBox(height: spacing.s3),
          ],
        ],
      ),
    );
  }

  static const double _headerWidth = 160;
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    return Row(
      children: <Widget>[
        CommySkeleton(
          width: CommySizes.flagWidth,
          height: CommySizes.flagHeight,
          borderRadius: context.radii.xsAll,
        ),
        SizedBox(width: spacing.s3),
        const Expanded(child: CommySkeleton()),
        SizedBox(width: spacing.s3),
        const CommySkeleton(width: _latencyWidth),
      ],
    );
  }

  static const double _latencyWidth = 40;
}
