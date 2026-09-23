import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';

/// A block of the server list, inset from the screen's edges and drawn as a
/// card the way the subscription cards are.
///
/// The list used to run from glass to glass: the rows that belong to no
/// subscription — Auto, servers added by hand — had no card at all, and the
/// subscription cards, rounded and bordered, sat flush against both edges, so
/// their corners met the screen and the whole list read as stretched to full
/// width. Every block now keeps `spacing.s4` from each side, which is the
/// margin the settings screen has always had.
///
/// [ListCard.inset] is for a block that draws its own card — the subscription
/// card does — and only needs the margin.
class ListCard extends StatelessWidget {
  /// Creates a card around [children].
  const ListCard({required List<Widget> this.children, super.key})
      : child = null;

  /// Insets [child], which already is a card, without drawing another.
  const ListCard.inset({required Widget this.child, super.key})
      : children = null;

  /// The rows of the card.
  final List<Widget>? children;

  /// A card of its own, only inset.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = children;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.s4),
      child: rows == null
          ? child
          : Container(
              // The same surface, corner, hairline and shadow as
              // `SubscriptionCard`, so the blocks read as one kind of thing.
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.bgSurface,
                borderRadius: context.radii.mdAll,
                border: Border.all(color: colors.borderSubtle),
                boxShadow: context.elevation.level1,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: rows,
              ),
            ),
    );
  }
}
