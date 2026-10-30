import 'package:commy_ui/src/components/atoms/commy_divider.dart';
import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// Which shape the bar takes.
enum _AppBarLayout {
  /// Root screen: the wordmark centred, controls on both sides.
  wordmark,

  /// A section opened from it: a back arrow and the section's name, left.
  section,
}

/// The top bar of every screen, in its two shapes
/// (docs/04-design-system.md §6).
///
/// The root shape: the cog on the left, the plus on the right, and the name
/// of the app centred between them as an inline title — `bodyStrong`, in the
/// case it is written. It is deliberately quiet. The answer under it is the
/// largest thing on that screen, and a bar that competes with it is a bar in
/// the wrong place.
///
/// The section shape: a back arrow and the section's name in `title1`, both
/// on the leading edge. A centred title there would leave the back arrow
/// floating on its own.
///
/// The bar is the colour of the canvas and has no line under it — until
/// content scrolls beneath it. Then a hairline appears at its edge, the
/// scroll-edge effect of iOS: a divider only where the floating chrome
/// actually overlaps something.
///
/// **At most two controls a side**, asserted rather than merely written down.
/// A third one always turns out to be something that belonged in a menu.
///
/// Chrome is fixed height, so the bar clamps text scaling at [maxTextScale]
/// while the screen under it scales without a limit. This is what both
/// platforms do with their own bars, and it is the difference between a large
/// system font making the app more readable and it eating a third of the
/// window before anything has been read.
class CommyAppBar extends StatefulWidget implements PreferredSizeWidget {
  /// Creates the root bar: [title] centred as a wordmark.
  ///
  /// [leading] and [actions] are normally [CommyIconButton]s and are already
  /// translated — this package owns no strings.
  const CommyAppBar({
    required this.title,
    this.leading = const <Widget>[],
    this.actions = const <Widget>[],
    super.key,
  })  : onBack = null,
        backSemanticLabel = null,
        _layout = _AppBarLayout.wordmark;

  /// Creates the bar of a screen opened from the root one.
  ///
  /// [onBack] of `null` drops the arrow, for a section that is somebody's
  /// root — a tablet detail pane, for instance.
  const CommyAppBar.section({
    required this.title,
    required this.onBack,
    this.backSemanticLabel,
    this.actions = const <Widget>[],
    super.key,
  })  : leading = const <Widget>[],
        _layout = _AppBarLayout.section,
        assert(
          onBack == null || backSemanticLabel != null,
          'A back arrow needs a label: a bare chevron says nothing to a '
          'screen reader.',
        );

  /// Highest text scale the bar itself honours. Beyond it the bar stops
  /// growing; the screen under it does not.
  static const double maxTextScale = 1.4;

  /// The wordmark, or the section's name. Already translated, drawn as given.
  final String title;

  /// Controls on the leading side, at most two. Empty in the section shape,
  /// which puts the back arrow there instead.
  final List<Widget> leading;

  /// Controls on the trailing side, at most two.
  final List<Widget> actions;

  /// Back handler of the section shape. `null` in the root shape.
  final VoidCallback? onBack;

  /// Announced for the back arrow.
  final String? backSemanticLabel;

  final _AppBarLayout _layout;

  @override
  Size get preferredSize => const Size.fromHeight(CommySizes.appBarHeight);

  @override
  State<CommyAppBar> createState() => _CommyAppBarState();
}

class _CommyAppBarState extends State<CommyAppBar> {
  ScrollNotificationObserverState? _observer;
  bool _scrolledUnder = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _observer?.removeListener(_onScroll);
    _observer = ScrollNotificationObserver.maybeOf(context);
    _observer?.addListener(_onScroll);
  }

  @override
  void dispose() {
    _observer?.removeListener(_onScroll);
    super.dispose();
  }

  /// The scaffold's own scroll view, and only it, decides the hairline: a
  /// horizontal strip of chips scrolling inside the page says nothing about
  /// what lies under the bar.
  void _onScroll(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return;
    }
    final under = notification.metrics.extentBefore > 0;
    if (under != _scrolledUnder) {
      setState(() => _scrolledUnder = under);
    }
  }

  @override
  Widget build(BuildContext context) {
    final widget = this.widget;
    final leading = widget.leading;
    final actions = widget.actions;
    final title = widget.title;
    // Not constructor asserts: `List.length` cannot be evaluated in a const
    // context, and a bar with a fixed title is worth keeping const-capable.
    assert(
      leading.length <= 2,
      'At most two controls on the leading side. A third one belongs in a '
      'menu.',
    );
    assert(
      actions.length <= 2,
      'At most two controls on the trailing side. A third one belongs in a '
      'menu.',
    );

    final colors = context.colors;
    final type = context.typography;
    final spacing = context.spacing;

    final Widget content;
    switch (widget._layout) {
      case _AppBarLayout.wordmark:
        content = Stack(
          children: <Widget>[
            Center(
              child: Padding(
                // Keeps the wordmark clear of the controls on both sides.
                padding: EdgeInsets.symmetric(
                  horizontal: CommySizes.iconButtonSize * 2 + spacing.s2,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                ...leading,
                const Spacer(),
                ...actions,
              ],
            ),
          ],
        );
      case _AppBarLayout.section:
        final back = widget.onBack;
        content = Row(
          children: <Widget>[
            if (back != null)
              CommyIconButton(
                icon: CommyIcons.chevronLeft,
                onPressed: back,
                semanticLabel: widget.backSemanticLabel!,
              )
            else
              SizedBox(width: spacing.s2),
            Expanded(
              child: Padding(
                padding: EdgeInsetsDirectional.only(start: spacing.s2),
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.title1.copyWith(color: colors.textPrimary),
                  ),
                ),
              ),
            ),
            ...actions,
          ],
        );
    }

    return ColoredBox(
      color: colors.bgCanvas,
      child: SafeArea(
        bottom: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: CommyAppBar.maxTextScale,
          child: SizedBox(
            height: CommySizes.appBarHeight,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: spacing.s1),
                    child: content,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: AnimatedOpacity(
                    opacity: _scrolledUnder ? 1 : 0,
                    duration: context.motion.instant,
                    curve: context.motion.instantCurve,
                    child: const CommyDivider(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
