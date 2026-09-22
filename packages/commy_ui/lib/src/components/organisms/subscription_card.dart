import 'package:commy_ui/src/components/atoms/commy_divider.dart';
import 'package:commy_ui/src/components/atoms/commy_icon_button.dart';
import 'package:commy_ui/src/components/atoms/commy_spinner.dart';
import 'package:commy_ui/src/components/commy_icons.dart';
import 'package:commy_ui/src/components/commy_tone.dart';
import 'package:commy_ui/src/components/molecules/quota_bar.dart';
import 'package:commy_ui/src/theme/context_extensions.dart';
import 'package:commy_ui/src/tokens/sizes.dart';
import 'package:flutter/material.dart';

/// How healthy a subscription is, as the leading glyph of the card shows it.
///
/// The glyph changes shape with the state, not only colour: a subscription in
/// trouble has to be recognisable without seeing the hue.
enum SubscriptionHealth {
  /// Fetched fine; quota and expiry are comfortable.
  ok,

  /// Nearly out of quota, or close to expiring.
  warning,

  /// The last refresh failed, or the subscription has run out.
  error;

  /// Meaning this state carries.
  CommyTone get tone => switch (this) {
        SubscriptionHealth.ok => CommyTone.connected,
        SubscriptionHealth.warning => CommyTone.connecting,
        SubscriptionHealth.error => CommyTone.error,
      };

  /// Lucide glyph for this state.
  IconData get icon => switch (this) {
        SubscriptionHealth.ok => CommyIcons.proxy,
        SubscriptionHealth.warning => CommyIcons.warning,
        SubscriptionHealth.error => CommyIcons.error,
      };
}

/// One link the panel advertises: its own web page, a support contact.
///
/// Links live in the footer of [SubscriptionCard] rather than inline with the
/// announcement, so that they stay in one place no matter how much the admin
/// wrote about themselves.
@immutable
class SubscriptionCardLink {
  /// Creates a footer link.
  const SubscriptionCardLink({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// Text of the link. Already translated.
  final String label;

  /// Lucide glyph shown before the label.
  final IconData icon;

  /// What happens on tap. Opening an external page is the app's decision, not
  /// this package's — rule R1 lives above the design system.
  final VoidCallback onPressed;
}

/// A subscription and its nodes, as one card.
///
/// This is the single most important structural decision on the main screen
/// (docs/05-ux-flows.md, scenario 4): the header sits on `bg/group-header`,
/// the node rows on `bg/surface`, and that step in background is the only
/// thing tying a subscription to its servers. Split into a card per node and
/// the list reads as unrelated blocks — nobody can tell which server belongs
/// to which subscription, and the whole screen stops making sense.
///
/// The header carries **exactly three** actions: refresh, ping every node,
/// and an overflow menu. The first two are pressed often, so they are
/// outside; everything rare — collapse, rename, copy link, update interval,
/// delete — belongs in the menu.
class SubscriptionCard extends StatelessWidget {
  /// Creates a subscription card.
  const SubscriptionCard({
    required this.name,
    required this.refreshLabel,
    required this.pingAllLabel,
    required this.moreLabel,
    this.subtitle,
    this.health = SubscriptionHealth.ok,
    this.healthSemanticLabel,
    this.quotaRatio,
    this.quotaLabel,
    this.expiryLabel,
    this.quotaSemanticLabel,
    this.announcement,
    this.links = const <SubscriptionCardLink>[],
    this.nodes = const <Widget>[],
    this.isCollapsed = false,
    this.isRefreshing = false,
    this.onRefresh,
    this.onPingAll,
    this.onMore,
    super.key,
  });

  /// Name of the subscription, as the user or the panel calls it.
  final String name;

  /// Announced and shown for the refresh action. Already translated.
  final String refreshLabel;

  /// Announced and shown for the "measure every node" action.
  final String pingAllLabel;

  /// Announced and shown for the overflow menu.
  final String moreLabel;

  /// Second line of the header: when it was last fetched and how often it
  /// refreshes itself, for example `2 ч назад · авто 1 ч`. Already composed
  /// and translated by the caller — this package owns no strings.
  final String? subtitle;

  /// State of the subscription, drawn as the leading glyph.
  final SubscriptionHealth health;

  /// Announced for that glyph. Without it the glyph is decoration.
  final String? healthSemanticLabel;

  /// Share of the quota already spent, in `0..1`, or `null` when the panel
  /// reported no quota at all. No bar is drawn in that case: inventing one is
  /// worse than showing nothing.
  final double? quotaRatio;

  /// Volume line under the bar, for example `1,12 ТБ из 2 ТБ`.
  final String? quotaLabel;

  /// Expiry line opposite it, for example `осталось 18 дней`.
  final String? expiryLabel;

  /// One sentence announced in place of the two labels and the bar.
  final String? quotaSemanticLabel;

  /// The free-text line the panel admin wrote for their own users.
  ///
  /// Rendered as-is, on one line, in monospace. Rewriting or truncating it is
  /// not our call: it is often where the support contact actually lives.
  final String? announcement;

  /// Links the panel advertises, shown as a footer panel behind a divider.
  final List<SubscriptionCardLink> links;

  /// The node rows, normally `NodeTile`s. Separated by a hairline; the last
  /// one gets none, so the card ends on a clean edge.
  final List<Widget> nodes;

  /// Whether the node rows are folded away. Collapsing lives in the overflow
  /// menu, so this widget only renders the result.
  final bool isCollapsed;

  /// Whether a refresh is running. The refresh button becomes a spinner in
  /// place, which keeps the three actions from shifting sideways.
  final bool isRefreshing;

  /// Refresh handler.
  final VoidCallback? onRefresh;

  /// "Measure every node in this subscription" handler.
  final VoidCallback? onPingAll;

  /// Overflow menu handler.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radii = context.radii;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: radii.mdAll,
        border: Border.all(color: colors.borderSubtle),
        boxShadow: context.elevation.level1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Header(
            name: name,
            subtitle: subtitle,
            health: health,
            healthSemanticLabel: healthSemanticLabel,
            quotaRatio: quotaRatio,
            quotaLabel: quotaLabel,
            expiryLabel: expiryLabel,
            quotaSemanticLabel: quotaSemanticLabel,
            announcement: announcement,
            links: links,
            refreshLabel: refreshLabel,
            pingAllLabel: pingAllLabel,
            moreLabel: moreLabel,
            isRefreshing: isRefreshing,
            onRefresh: onRefresh,
            onPingAll: onPingAll,
            onMore: onMore,
          ),
          if (!isCollapsed)
            for (var index = 0; index < nodes.length; index++) ...<Widget>[
              if (index > 0) const CommyDivider(),
              nodes[index],
            ],
        ],
      ),
    );
  }
}

/// Everything standing on `bg/group-header`: title, actions, quota, the
/// admin's own line and the footer of links.
class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.subtitle,
    required this.health,
    required this.healthSemanticLabel,
    required this.quotaRatio,
    required this.quotaLabel,
    required this.expiryLabel,
    required this.quotaSemanticLabel,
    required this.announcement,
    required this.links,
    required this.refreshLabel,
    required this.pingAllLabel,
    required this.moreLabel,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onPingAll,
    required this.onMore,
  });

  final String name;
  final String? subtitle;
  final SubscriptionHealth health;
  final String? healthSemanticLabel;
  final double? quotaRatio;
  final String? quotaLabel;
  final String? expiryLabel;
  final String? quotaSemanticLabel;
  final String? announcement;
  final List<SubscriptionCardLink> links;
  final String refreshLabel;
  final String pingAllLabel;
  final String moreLabel;
  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final VoidCallback? onPingAll;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;
    final type = context.typography;
    final ratio = quotaRatio;
    final volume = quotaLabel;
    final expiry = expiryLabel;
    final note = announcement;
    final hasLabels = volume != null || expiry != null;

    return ColoredBox(
      color: colors.bgGroupHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: spacing.s4,
              top: spacing.s2,
              end: spacing.s2,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  padding: EdgeInsets.all(spacing.s2),
                  decoration: BoxDecoration(
                    color: health.tone.wash(colors),
                    borderRadius: context.radii.smAll,
                  ),
                  child: Icon(
                    health.icon,
                    size: CommySizes.iconControl,
                    color: health.tone.foreground(colors),
                    semanticLabel: healthSemanticLabel,
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
                if (isRefreshing)
                  SizedBox(
                    width: CommySizes.iconButtonSize,
                    height: CommySizes.iconButtonSize,
                    child: Center(
                      child: CommySpinner(semanticLabel: refreshLabel),
                    ),
                  )
                else if (onRefresh != null)
                  CommyIconButton(
                    icon: CommyIcons.refresh,
                    onPressed: onRefresh,
                    semanticLabel: refreshLabel,
                    tooltip: refreshLabel,
                  ),
                if (onPingAll != null)
                  CommyIconButton(
                    icon: CommyIcons.diagnostics,
                    onPressed: onPingAll,
                    semanticLabel: pingAllLabel,
                    tooltip: pingAllLabel,
                  ),
                if (onMore != null)
                  CommyIconButton(
                    icon: CommyIcons.more,
                    onPressed: onMore,
                    semanticLabel: moreLabel,
                    tooltip: moreLabel,
                  ),
              ],
            ),
          ),
          if (ratio != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.s4),
              child: QuotaBar(
                ratio: ratio,
                semanticLabel: quotaSemanticLabel,
              ),
            ),
          if (hasLabels)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: spacing.s4,
                top: spacing.s2,
                end: spacing.s4,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      volume ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  if (expiry != null) ...<Widget>[
                    SizedBox(width: spacing.s2),
                    Flexible(
                      child: Text(
                        expiry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // The gap that used to sit below the notice now sits inside it,
          // as the lower half of the tap target. Same pixels, 52pt to hit.
          if (note != null)
            _Announcement(note)
          else
            SizedBox(height: spacing.s3),
          if (links.isNotEmpty) ...<Widget>[
            const CommyDivider(),
            Row(
              children: <Widget>[
                for (final link in links)
                  Expanded(child: _ProviderLink(link: link)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One footer link. A full-width, 48 dp tap target — these are pressed with a
/// thumb, at the bottom of a card, often in a hurry.
class _ProviderLink extends StatelessWidget {
  const _ProviderLink({required this.link});

  final SubscriptionCardLink link;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Semantics(
      button: true,
      label: link.label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: link.onPressed,
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    link.icon,
                    size: CommySizes.iconInline,
                    color: colors.textSecondary,
                  ),
                  SizedBox(width: spacing.s2),
                  Flexible(
                    child: Text(
                      link.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.bodyStrong.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel's own message to its users, one line until asked for the rest.
///
/// It used to be one line, full stop: a 529-character notice about tonight's
/// maintenance arrived, was stored, and showed 45 characters of itself with
/// no way anywhere in the app to read the rest. This is the only channel the
/// person who runs the panel has, so the text has to be reachable — and it
/// cannot be reachable by pushing the server list off the screen, which is
/// why the default is still one line.
///
/// The state is local on purpose. Which notice a user has read is not worth a
/// column in the database, and reopening the screen on the short form is the
/// right default anyway.
class _Announcement extends StatefulWidget {
  const _Announcement(this.note);

  final String note;

  @override
  State<_Announcement> createState() => _AnnouncementState();
}

class _AnnouncementState extends State<_Announcement> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final spacing = context.spacing;

    return Semantics(
      button: true,
      expanded: _expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: spacing.s4,
            top: spacing.s2,
            end: spacing.s4,
            bottom: spacing.s3,
          ),
          // No `minHeight` here, and not for want of the rule: two lines of
          // `monoSmall` plus this padding clear the 48pt floor on their own,
          // and a constraint on top of that only padded the card with air.
          // Measured: 388x52.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.note,
                  // Two lines collapsed, not one: it is the difference
                  // between "Уважаемые пользователи! 24 сент…" and a
                  // sentence a person can act on, and it costs one line of
                  // a card that is 250pt tall.
                  maxLines: _expanded ? null : 2,
                  overflow:
                      _expanded ? TextOverflow.clip : TextOverflow.ellipsis,
                  style: context.typography.monoSmall
                      .copyWith(color: colors.textTertiary),
                ),
              ),
              SizedBox(width: spacing.s2),
              Icon(
                _expanded ? CommyIcons.chevronUp : CommyIcons.chevronDown,
                size: CommySizes.iconInline,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
