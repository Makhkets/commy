import 'package:commy_ui/src/components/commy_focusable.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/country_flag.dart';
import 'package:commy_ui/src/components/molecules/latency_badge.dart';
import 'package:commy_ui/src/components/molecules/node_tag_line.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// One server, as a row inside the card of the subscription it came from.
///
/// The active node is a rounded plate inset from the card — the connected
/// wash with a hairline of the connected fill around it, `block` (16) inside
/// the card's 20 — never a tick on the trailing side. It used to be a bar
/// down the leading edge; the plate is INCY's, which the owner pointed at
/// (2026-10-10): it is caught by peripheral vision just as well while
/// scrolling, costs no width either, and reads as "this one" rather than as
/// a stripe on the card's edge.
///
/// Every row is inset by `space/1` on each side, so the plate and the press
/// highlight of any row are the same rounded shape, concentric with the card
/// (`card − 4`). A container that wants the plate as far from its top edge
/// as from its sides pads the block of rows by another `space/1`.
///
/// An unreachable node is greyed — flag, text and tags — and given the
/// offline glyph, but never hidden: a server that timed out once may be fine
/// a minute later. Hiding dead nodes is a separate, explicit switch
/// (docs/05-ux-flows.md, scenario 4). The glyph matters: grey alone is a
/// colour signal, and colour is never allowed to carry a meaning on its own.
///
/// Latency comes from [LatencyBadge], which shows bars *and* a number *and* a
/// colour for the same reason.
///
/// Keyboard and D-pad focus is the 2 px `border/strong` ring the rest of the
/// system uses ([CommyFocusable]), drawn over the row — never the ink fill
/// Material paints by default. That fill (12 % black or white) is laid under
/// the text and took the protocol tags below AA, worst on the active plate.
/// Hover keeps its `accent/wash`, except over the plate, which is already
/// the row's highlight.
class NodeTile extends StatelessWidget {
  /// Creates a node row.
  const NodeTile({
    required this.name,
    this.descriptors = const <NodeTag>[],
    this.latency,
    this.countryCode,
    this.isActive = false,
    this.isLive = true,
    this.isReachable = true,
    this.offlineSemanticLabel,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// What joins two descriptors written out as one string — a toast, an
  /// announcement: `VLESS, Reality, TCP`. On screen the line is
  /// [NodeTagLine], which leaves a gap instead.
  static const String descriptorSeparator = ', ';

  /// Takes the colour out of a flag and keeps its light and dark, so it
  /// stays a flag — only a grey one. Rec. 709 luma weights; not a design
  /// token, the same way the geometry inside a flag is not.
  static const ColorFilter _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Display name, as the panel wrote it.
  final String name;

  /// The second line, drawn by [NodeTagLine].
  ///
  /// For a server it is protocol, security and transport, in that order, and
  /// those are wire names rather than words — `VLESS`, `Reality`, `TCP` — so
  /// they are not translated and must not be; each carries the hue the app
  /// gave it. The Auto row uses the same line for something else: the name of
  /// the server its group landed on, or a sentence saying it has not landed
  /// on one yet, without a hue. Either way the text arrives finished — this
  /// widget draws it and translates nothing.
  final List<NodeTag> descriptors;

  /// Last measured round trip, or `null` when the node was never probed.
  final Duration? latency;

  /// ISO 3166-1 alpha-2 code of the country the node sits in, as
  /// `ProxyNode.countryCode` carries it.
  ///
  /// The flag is always drawn, including when this is `null` or unrecognised:
  /// [CountryFlag] then paints its neutral chip, which keeps every node name
  /// in the list starting on the same column. A row that dropped the flag
  /// would pull its name left and break the one alignment the eye uses to
  /// scan a long list.
  final String? countryCode;

  /// Whether this is the chosen node.
  final bool isActive;

  /// Whether traffic goes through the chosen node right now.
  ///
  /// The plate of a chosen node is green only then: green says "connected"
  /// and nothing else (docs/04-design-system.md §2). Chosen while the tunnel
  /// is down, the plate is the neutral fill with a `line-strong` edge — the
  /// choice, without a claim about the connection.
  final bool isLive;

  /// Whether the last probe reached the server.
  final bool isReachable;

  /// Announced for the offline glyph shown when [isReachable] is false.
  final String? offlineSemanticLabel;

  /// Tap handler. Selecting a node is what this row is for.
  final VoidCallback? onTap;

  /// Long-press handler, for the per-node menu.
  final VoidCallback? onLongPress;

  /// The second line of the row, already joined. Empty when there is none.
  String get descriptorLine =>
      descriptors.map((tag) => tag.label).join(descriptorSeparator);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final motion = context.motion;
    final shape = context.radii.blockAll;

    // A server that did not answer is grey: its flag loses its colour and its
    // name drops to the tertiary step. One step down used to be all it got,
    // and on a phone that read as "the same row, slightly lighter" — the
    // owner could not tell at a glance which servers had failed their ping.
    // Still not `textDisabled`: that is for a control a tap cannot reach, it
    // is 2.0:1 against the surface in the light theme, and this row is still
    // tappable. Tertiary clears WCAG AA here, including on the connected
    // wash of the active row (4.5:1 in both themes, the tightest case).
    final nameColor = isReachable ? colors.textPrimary : colors.textTertiary;
    final metaColor = isReachable ? colors.textSecondary : colors.textTertiary;
    final flag = CountryFlag(countryCode: countryCode);

    return Semantics(
      selected: isActive,
      button: onTap != null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.s1,
          vertical: spacing.s05,
        ),
        child: CommyFocusable(
          onActivate: onTap,
          builder: (context, {required isFocused}) => AnimatedContainer(
            duration: motion.fast,
            curve: motion.fastCurve,
            decoration: BoxDecoration(
              color: !isActive
                  ? CommyColors.transparent
                  : isLive
                      ? colors.statusConnectedWash
                      : colors.fill,
              borderRadius: shape,
              border: Border.all(
                color: !isActive
                    ? CommyColors.transparent
                    : isLive
                        ? colors.statusConnectedSolid
                        : colors.borderStrong,
              ),
            ),
            // Over the content, so the ring costs no layout and never moves
            // the row by its width.
            foregroundDecoration: BoxDecoration(
              borderRadius: shape,
              border: CommyFocusable.ring(colors, isFocused: isFocused),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                onLongPress: onLongPress,
                // Focus belongs to the CommyFocusable around it.
                canRequestFocus: false,
                hoverColor: isActive ? CommyColors.transparent : null,
                customBorder: RoundedRectangleBorder(borderRadius: shape),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: CommySizes.minTapTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.s3,
                      vertical: spacing.s2,
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: CommySizes.flagTile,
                          height: CommySizes.flagTile,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.bgOverlay,
                            borderRadius: context.radii.smAll,
                          ),
                          child: isReachable
                              ? flag
                              : ColorFiltered(
                                  colorFilter: _greyscale,
                                  child: flag,
                                ),
                        ),
                        SizedBox(width: spacing.s3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.title3.copyWith(color: nameColor),
                              ),
                              if (descriptors.isNotEmpty)
                                NodeTagLine(
                                  tags: descriptors,
                                  muted: !isReachable,
                                  mutedColor: metaColor,
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: spacing.s3),
                        if (!isReachable) ...<Widget>[
                          Icon(
                            CommyIcons.offline,
                            size: CommySizes.iconInline,
                            // Same reason as the name above: this glyph is
                            // the state, not a dead control.
                            color: colors.textTertiary,
                            semanticLabel: offlineSemanticLabel,
                          ),
                          SizedBox(width: spacing.s2),
                        ],
                        LatencyBadge(latency: isReachable ? latency : null),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
