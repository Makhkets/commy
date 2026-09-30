import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/widgets.dart';

/// A word that does something inside a toast or a banner: "Undo", "Retry",
/// "Settings".
///
/// It used to be a bare `Text` under a `GestureDetector`, which takes a tap
/// on the line box of the glyphs and nowhere else — 22 pt tall where this
/// design system's floor is 48 — with no button role and no focus. "Вернуть"
/// is the only undo for a routing rule deleted with a swipe, and it is gone
/// after six seconds: a thumb that landed under the word missed it, and the
/// rule went with it.
///
/// The word keeps its look. Around it is a box of at least
/// [CommySizes.minTapTarget] each way that takes the tap, is announced as a
/// button and takes keyboard focus. The box is air, and the caller makes the
/// room for it out of its own padding rather than growing by it.
///
/// Internal to this package: screens get it through `Toast` and
/// `ErrorBanner`, never on its own.
class CommyInlineAction extends StatelessWidget {
  /// Creates the action.
  const CommyInlineAction({
    required this.label,
    required this.onPressed,
    required this.color,
    super.key,
  });

  /// The word. Already translated.
  final String label;

  /// What a tap, Space or Enter does. `null` leaves a word that does nothing.
  final VoidCallback? onPressed;

  /// Colour of the word: the tone of the toast or banner it sits in.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Semantics(
      // Its own node: the toast around it is one live region, and without
      // this the whole toast would be announced as the button.
      container: true,
      button: true,
      enabled: onPressed != null,
      child: CommyFocusable(
        onActivate: onPressed,
        builder: (context, {required isFocused}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: CommySizes.minTapTarget,
                  minHeight: CommySizes.minTapTarget,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    style: context.typography.bodyStrong.copyWith(color: color),
                  ),
                ),
              ),
              // The focus ring, with air on either side of the word. The
              // box is as wide as the word, so a ring on its edge touched
              // the first and last letter; this one reaches past the box
              // into the gap the caller already leaves, and moves nothing.
              Positioned(
                left: -spacing.s2,
                right: -spacing.s2,
                top: spacing.s1,
                bottom: spacing.s1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: context.radii.xsAll,
                      border: CommyFocusable.ring(
                        context.colors,
                        isFocused: isFocused,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
