import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// Modal content, presented the way the current window wants it.
///
/// **One API.** Callers say `CommySheet.show(...)` and never look at the
/// platform or the width: below `CommyBreakpoints.expanded` the content
/// arrives as a bottom sheet with a drag handle, above it as a centred dialog
/// no wider than [CommySizes.dialogMaxWidth]. The moment a screen writes
/// `if (Platform.isAndroid)` around a modal, the two presentations start
/// drifting apart and one of them quietly rots.
///
/// The chrome — corner radius, handle, scrim, title — is [CommySheetSurface],
/// which callers can also use directly when they need to embed the same
/// treatment somewhere that is not a route.
abstract final class CommySheet {
  /// Presents [builder] and completes with whatever the route was popped with.
  ///
  /// [title] is already translated and is rendered in `Title/2` above the
  /// content. [isDismissible] false makes the modal insistent: the scrim stops
  /// closing it and the drag handle disappears. Use it only where losing what
  /// the user typed would be worse than one extra tap.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    bool isDismissible = true,
  }) {
    final colors = context.colors;
    if (context.layoutSize.prefersDialog) {
      return showDialog<T>(
        context: context,
        barrierDismissible: isDismissible,
        barrierColor: colors.bgScrim,
        builder: (context) => Dialog(
          backgroundColor: CommyColors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.all(context.spacing.s6),
          child: CommySheetSurface(
            title: title,
            isDialog: true,
            child: Builder(builder: builder),
          ),
        ),
      );
    }

    return showModalBottomSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: CommyColors.transparent,
      barrierColor: colors.bgScrim,
      elevation: 0,
      builder: (context) => CommySheetSurface(
        title: title,
        showHandle: isDismissible,
        child: Builder(builder: builder),
      ),
    );
  }
}

/// The chrome of a modal: raised surface, corners, optional handle and title.
///
/// Split out of [CommySheet] so that the two presentations cannot drift, and
/// so that a golden test can photograph the surface without driving a route.
class CommySheetSurface extends StatelessWidget {
  /// Creates the surface.
  const CommySheetSurface({
    required this.child,
    this.title,
    this.showHandle = true,
    this.isDialog = false,
    super.key,
  });

  /// Content of the modal.
  final Widget child;

  /// Heading in `Title/2`. Already translated. `null` draws no heading.
  final String? title;

  /// Whether the drag handle is drawn. Ignored when [isDialog]: a dialog is
  /// not dragged anywhere, so a handle on one would be a lie.
  final bool showHandle;

  /// Whether this is the dialog presentation — all four corners rounded, no
  /// handle, width capped at [CommySizes.dialogMaxWidth].
  final bool isDialog;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final radii = context.radii;
    final heading = title;

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bgRaised,
        borderRadius: isDialog ? radii.lgAll : radii.lgTop,
        border: Border.all(color: colors.borderDefault),
        boxShadow: context.elevation.level2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (!isDialog && showHandle) ...<Widget>[
            SizedBox(height: spacing.s2),
            Center(
              child: SizedBox(
                width: CommySizes.sheetHandleWidth,
                height: CommySizes.sheetHandleHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: radii.fullAll,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
          if (heading != null) ...<Widget>[
            SizedBox(height: spacing.s5),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s5),
              child: Semantics(
                header: true,
                child: Text(
                  heading,
                  style: context.typography.title2.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.only(
              top: spacing.s4,
              bottom: spacing.s5,
            ),
            child: child,
          ),
        ],
      ),
    );

    if (!isDialog) {
      return surface;
    }
    // No `Center` here on purpose: the route already centres the surface, and
    // wrapping it would make this widget report the whole window as its own
    // size — which is exactly the sort of thing a layout test then cannot see.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: CommySizes.dialogMaxWidth),
      child: surface,
    );
  }
}
