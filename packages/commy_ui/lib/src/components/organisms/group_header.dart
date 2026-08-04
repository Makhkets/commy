import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// The header of a group of nodes the user added by hand.
///
/// It is the plain sibling of `SubscriptionCard`: same step in background,
/// same title block, same actions on the trailing side — but no quota, no
/// expiry and no panel announcement, because a hand-made group has none of
/// those. Only two actions are offered here: a manual group has nothing to
/// refresh.
///
/// This widget is the header **bar** and nothing else. Its corners are square
/// and it paints edge to edge, so the screen can put it and its node rows
/// inside one clipped surface and keep the "a group is one card" rule that
/// docs/05-ux-flows.md scenario 4 spells out.
class GroupHeader extends StatelessWidget {
  /// Creates a group header.
  const GroupHeader({
    required this.title,
    this.subtitle,
    this.leading,
    this.isCollapsed = false,
    this.collapseLabel,
    this.pingAllLabel,
    this.moreLabel,
    this.onToggleCollapse,
    this.onPingAll,
    this.onMore,
    super.key,
  })  : assert(
          onToggleCollapse == null || collapseLabel != null,
          'A collapse control needs a label: a bare chevron says nothing to '
          'a screen reader.',
        ),
        assert(
          onPingAll == null || pingAllLabel != null,
          'A ping-all control needs a label.',
        ),
        assert(
          onMore == null || moreLabel != null,
          'An overflow control needs a label.',
        );

  /// Name of the group.
  final String title;

  /// Second line: what the group is and how much is in it, for example
  /// `добавлены вручную · 1 узел`. Already composed and translated.
  final String? subtitle;

  /// Optional glyph before the title, when the screen has one to give.
  final Widget? leading;

  /// Whether the group is currently folded away.
  final bool isCollapsed;

  /// Announced for the collapse control. Required when [onToggleCollapse] is
  /// given.
  final String? collapseLabel;

  /// Announced for the "measure every node" control. Required when
  /// [onPingAll] is given.
  final String? pingAllLabel;

  /// Announced for the overflow menu. Required when [onMore] is given.
  final String? moreLabel;

  /// Fold and unfold handler. No control is drawn when this is `null`.
  final VoidCallback? onToggleCollapse;

  /// "Measure every node in this group" handler.
  final VoidCallback? onPingAll;

  /// Overflow menu handler.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final leadingWidget = leading;
    final collapse = onToggleCollapse;

    return ColoredBox(
      color: colors.bgGroupHeader,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: CommySizes.minTapTarget,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.s4,
            top: spacing.s2,
            end: spacing.s2,
            bottom: spacing.s2,
          ),
          child: Row(
            children: <Widget>[
              if (leadingWidget != null) ...<Widget>[
                leadingWidget,
                SizedBox(width: spacing.s3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.title3.copyWith(color: colors.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (collapse != null)
                CommyIconButton(
                  icon: isCollapsed
                      ? CommyIcons.chevronDown
                      : CommyIcons.chevronUp,
                  onPressed: collapse,
                  semanticLabel: collapseLabel!,
                  tooltip: collapseLabel,
                ),
              if (onPingAll != null)
                CommyIconButton(
                  icon: CommyIcons.diagnostics,
                  onPressed: onPingAll,
                  semanticLabel: pingAllLabel!,
                  tooltip: pingAllLabel,
                ),
              if (onMore != null)
                CommyIconButton(
                  icon: CommyIcons.more,
                  onPressed: onMore,
                  semanticLabel: moreLabel!,
                  tooltip: moreLabel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
