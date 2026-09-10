import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `Замерено 8 из 24` and a way to stop, above the servers being measured.
///
/// Sits inside the card's node list rather than in its header because the
/// header is a fixed three controls in docs/05-ux-flows.md, and because the
/// progress belongs next to the rows whose numbers are changing.
class MeasureProgressRow extends ConsumerWidget {
  /// Creates the row.
  const MeasureProgressRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;
    final progress = ref.watch(measurementProvider);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s4,
        vertical: spacing.s2,
      ),
      child: Row(
        children: <Widget>[
          CommySpinner(semanticLabel: t.subscription.pingAll),
          SizedBox(width: spacing.s3),
          Expanded(
            child: Text(
              t.home.measuring(
                done: progress.done,
                total: progress.total,
              ),
              style: context.typography.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          CommyButton(
            label: t.common.cancel,
            variant: CommyButtonVariant.ghost,
            onPressed: ref.read(measurementProvider.notifier).cancel,
          ),
        ],
      ),
    );
  }
}
