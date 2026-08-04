import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/src/components/atoms/commy_badge.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// One routing rule, as a row of the ordered rule list.
///
/// The row leads with a drag handle because in this list **order is
/// priority**: the first rule that matches wins, and dragging is the plainest
/// way to say so. The handle is a full 48 dp target — a 16 dp glyph is not
/// something a thumb can pick up.
///
/// The matcher is monospace: `geosite:ru` and `domain_suffix:example.com` are
/// expressions, not prose. The action is a badge whose word carries the
/// meaning and whose colour only reinforces it.
///
/// The final rule — "everything else" — is not draggable and not deletable:
/// routing must have a last resort. Its handle slot stays in place so the
/// rows above it do not shift sideways, but it is inert and dimmed.
class RuleRow extends StatelessWidget {
  /// Creates a rule row.
  const RuleRow({
    required this.matcher,
    required this.actionLabel,
    required this.action,
    this.dragIndex,
    this.dragHandleLabel,
    this.isFinal = false,
    this.isEnabled = true,
    this.onTap,
    super.key,
  }) : assert(
          dragIndex == null || dragHandleLabel != null,
          'A draggable row needs a handle label: a grip glyph on its own '
          'says nothing to a screen reader.',
        );

  /// What the rule matches, in the core's own syntax. Shown as written.
  ///
  /// For the final rule this is the translated word for "everything else"
  /// instead of an expression, which is why [isFinal] also switches the type
  /// style away from monospace.
  final String matcher;

  /// The action, in words: `Прямо`, `Блок`, `Прокси`. Already translated;
  /// upper-cased on the way out by the badge.
  final String actionLabel;

  /// The action itself, which picks the tone of the badge.
  final RuleAction action;

  /// Position of this row inside its `ReorderableListView`.
  ///
  /// When given, the handle starts a drag. When `null` the handle is inert —
  /// which is what the final rule and any read-only list wants.
  final int? dragIndex;

  /// Announced for the drag handle. Required when [dragIndex] is given.
  final String? dragHandleLabel;

  /// Whether this is the terminal rule that cannot be moved or removed.
  final bool isFinal;

  /// Whether the rule is currently applied. A disabled rule stays visible and
  /// legible; it just stops shouting.
  final bool isEnabled;

  /// Tap handler, for editing the rule.
  final VoidCallback? onTap;

  /// Tone the action badge is drawn in.
  ///
  /// `proxy` is the only one that gets the signature hue, and it means the
  /// traffic goes through the tunnel — the same thing green means everywhere
  /// else in the product.
  CommyTone get tone => switch (action) {
        RuleAction.proxy => CommyTone.connected,
        RuleAction.direct => CommyTone.idle,
        RuleAction.block => CommyTone.error,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final index = dragIndex;

    final matcherStyle = isFinal ? type.body : type.monoStrong;
    final Color matcherColor;
    if (!isEnabled) {
      matcherColor = colors.textDisabled;
    } else {
      matcherColor = isFinal ? colors.textSecondary : colors.textPrimary;
    }

    final handle = _DragHandle(
      isActive: index != null && !isFinal,
      semanticLabel: dragHandleLabel,
    );

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: CommySizes.minTapTarget),
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: spacing.s4),
        child: Row(
          children: <Widget>[
            if (index != null && !isFinal)
              ReorderableDragStartListener(index: index, child: handle)
            else
              handle,
            Expanded(
              child: Text(
                matcher,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: matcherStyle.copyWith(color: matcherColor),
              ),
            ),
            SizedBox(width: spacing.s3),
            CommyBadge(
              label: actionLabel,
              tone: isEnabled ? tone : CommyTone.idle,
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      enabled: isEnabled,
      child: Material(
        color: colors.bgSurface,
        child: onTap == null
            ? row
            : InkWell(
                onTap: onTap,
                child: row,
              ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.isActive, required this.semanticLabel});

  final bool isActive;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: CommySizes.minTapTarget,
      height: CommySizes.minTapTarget,
      child: Icon(
        CommyIcons.drag,
        size: CommySizes.iconControl,
        color: isActive ? colors.textTertiary : colors.textDisabled,
        semanticLabel: isActive ? semanticLabel : null,
      ),
    );
  }
}
