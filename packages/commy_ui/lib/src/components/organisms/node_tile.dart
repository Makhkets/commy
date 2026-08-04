import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/country_flag.dart';
import 'package:commy_ui/src/components/molecules/latency_badge.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/colors.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// One server, as a row inside the card of the subscription it came from.
///
/// The active node is marked by a bar down the leading edge plus a tinted
/// row, never by a tick on the trailing side: a bar costs no width and is
/// caught by peripheral vision while scrolling, which is the whole job of
/// this row in a list the user flicks through looking for one name.
///
/// An unreachable node is dimmed and given the offline glyph, but never
/// hidden — a server that timed out once may be fine a minute later. Hiding
/// dead nodes is a separate, explicit switch (docs/05-ux-flows.md, scenario
/// 4). The glyph matters: dimming alone is a colour signal, and colour is
/// never allowed to carry a meaning on its own.
///
/// Latency comes from [LatencyBadge], which shows bars *and* a number *and* a
/// colour for the same reason.
class NodeTile extends StatelessWidget {
  /// Creates a node row.
  const NodeTile({
    required this.name,
    this.descriptors = const <String>[],
    this.latency,
    this.countryCode,
    this.isActive = false,
    this.isReachable = true,
    this.offlineSemanticLabel,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  /// What sits between two descriptors: `VLESS · Reality · TCP`.
  static const String descriptorSeparator = ' · ';

  /// Display name, as the panel wrote it.
  final String name;

  /// Protocol, security and transport, in that order, joined with
  /// [descriptorSeparator].
  ///
  /// These are wire names rather than words — `VLESS`, `Reality`, `TCP` — so
  /// they are not translated and must not be.
  final List<String> descriptors;

  /// Last measured round trip, or `null` when the node was never probed.
  final Duration? latency;

  /// ISO 3166-1 alpha-2 code of the country the node sits in, as
  /// `ProxyNode.countryCode` carries it.
  ///
  /// The flag is always drawn, including when this is `null` or unrecognised:
  /// [CountryFlag] then paints its neutral chip, which keeps every node name
  /// in the list starting on the same column. A row that dropped the flag
  /// would pull its name 38 dp left and break the one alignment the eye uses
  /// to scan a long list.
  final String? countryCode;

  /// Whether this is the node traffic currently goes through.
  final bool isActive;

  /// Whether the last probe reached the server.
  final bool isReachable;

  /// Announced for the offline glyph shown when [isReachable] is false.
  final String? offlineSemanticLabel;

  /// Tap handler. Selecting a node is what this row is for.
  final VoidCallback? onTap;

  /// Long-press handler, for the per-node menu.
  final VoidCallback? onLongPress;

  /// The second line of the row, already joined. Empty when there is none.
  String get descriptorLine => descriptors.join(descriptorSeparator);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final motion = context.motion;

    final nameColor = isReachable ? colors.textPrimary : colors.textDisabled;
    final metaColor = isReachable ? colors.textSecondary : colors.textDisabled;

    return Semantics(
      selected: isActive,
      button: onTap != null,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: motion.fastCurve,
        color: isActive ? colors.statusConnectedWash : CommyColors.transparent,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            child: Stack(
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: CommySizes.minTapTarget,
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      spacing.s4,
                      spacing.s3,
                      spacing.s4,
                      spacing.s3,
                    ),
                    child: Row(
                      children: <Widget>[
                        CountryFlag(countryCode: countryCode),
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
                                Text(
                                  descriptorLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: type.caption.copyWith(
                                    color: metaColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: spacing.s3),
                        if (!isReachable) ...<Widget>[
                          Icon(
                            CommyIcons.offline,
                            size: CommySizes.iconInline,
                            color: colors.textDisabled,
                            semanticLabel: offlineSemanticLabel,
                          ),
                          SizedBox(width: spacing.s2),
                        ],
                        LatencyBadge(latency: isReachable ? latency : null),
                      ],
                    ),
                  ),
                ),
                if (isActive)
                  PositionedDirectional(
                    top: 0,
                    bottom: 0,
                    start: 0,
                    width: CommySizes.activeMarkerWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.statusConnected,
                        borderRadius: BorderRadiusDirectional.horizontal(
                          end: Radius.circular(context.radii.full),
                        ),
                      ),
                      child: const SizedBox.expand(),
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
