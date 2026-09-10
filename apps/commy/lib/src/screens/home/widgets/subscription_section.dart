import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/screens/home/widgets/measure_progress_row.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy/src/screens/home/widgets/subscription_menu_sheet.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// One subscription and its servers, as a single card.
///
/// docs/05-ux-flows.md is explicit that these are not two blocks: the header
/// sits on `bg/overlay` and the rows on `bg/surface`, and the step in the
/// background is what makes the grouping obvious without a border. Splitting
/// them into separate cards is what made it unclear which server belonged to
/// which panel.
class SubscriptionSection extends ConsumerWidget {
  /// Creates the card.
  const SubscriptionSection({
    required this.subscription,
    required this.nodes,
    super.key,
  });

  /// The subscription to draw.
  final Subscription subscription;

  /// Its servers, already filtered by the caller.
  final List<ProxyNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Translations.of(context);
    final selectedId = ref.watch(selectedNodeIdProvider).value;
    final busy = ref.watch(subscriptionControllerProvider);
    final measuring = ref.watch(measurementProvider);
    final isMeasuringThis = measuring.scopeId == subscription.id;
    final info = subscription.userInfo;
    final now = ref.watch(clockProvider).value ?? DateTime.now();

    return SubscriptionCard(
      name: subscription.name,
      subtitle: _subtitle(t, now),
      refreshLabel: t.subscription.refresh,
      pingAllLabel: t.subscription.pingAll,
      moreLabel: t.subscription.more,
      health: _healthOf(info, now),
      healthSemanticLabel: t.a11y.subscriptionHealth,
      quotaRatio: info?.ratio,
      quotaLabel: _quotaLabel(t, info),
      expiryLabel: _expiryLabel(t, info, now),
      quotaSemanticLabel: _quotaSemantics(t, info),
      announcement: subscription.announcement,
      isRefreshing: busy.refreshingId == subscription.id,
      isCollapsed: subscription.isCollapsed,
      links: _links(t),
      onRefresh: () => unawaited(
        ref
            .read(subscriptionControllerProvider.notifier)
            .refresh(subscription.id),
      ),
      onPingAll: () => unawaited(
        ref.read(measurementProvider.notifier).measureAll(
              nodes,
              scopeId: subscription.id,
            ),
      ),
      onMore: () => unawaited(
        SubscriptionMenuSheet.show(
          context: context,
          subscription: subscription,
        ),
      ),
      nodes: <Widget>[
        if (isMeasuringThis) const MeasureProgressRow(),
        for (final node in nodes)
          NodeRow(node: node, isActive: node.id == selectedId),
      ],
    );
  }

  /// `2 ч назад · авто 1 ч`, or an honest "never" when it has not run.
  String _subtitle(Translations t, DateTime now) {
    final last = subscription.lastUpdatedAt;
    final parts = <String>[
      if (last == null)
        t.subscription.never
      else
        t.subscription.updatedAgo(
          time: RelativeTime.coarse(now.difference(last), t),
        ),
      if (subscription.autoUpdate)
        t.subscription.autoEvery(
          interval: RelativeTime.hours(subscription.updateInterval, t),
        ),
    ];
    return parts.join(NodeRow.separator);
  }

  String? _quotaLabel(Translations t, SubscriptionUserInfo? info) {
    if (info == null) {
      return null;
    }
    final used = info.usedBytes;
    final total = info.total;
    if (used == null) {
      return null;
    }
    if (total == null || total <= 0) {
      return t.subscription.unlimited;
    }
    return t.subscription.quota(
      used: CommyByteFormat.bytes(used),
      total: CommyByteFormat.bytes(total),
    );
  }

  String? _quotaSemantics(Translations t, SubscriptionUserInfo? info) {
    if (info == null) {
      return null;
    }
    final used = info.usedBytes;
    final total = info.total;
    if (used == null || total == null || total <= 0) {
      return null;
    }
    return t.a11y.quota(
      used: CommyByteFormat.bytes(used),
      total: CommyByteFormat.bytes(total),
    );
  }

  String? _expiryLabel(
    Translations t,
    SubscriptionUserInfo? info,
    DateTime now,
  ) {
    if (info == null || info.expire == null) {
      return null;
    }
    if (info.isExpiredAt(now)) {
      return t.subscription.expired;
    }
    final days = info.daysLeftAt(now) ?? 0;
    return t.subscription.daysLeft(count: t.subscription.days(count: days));
  }

  /// Tone of the card. Warns **before** the quota or the term runs out, which
  /// is the whole point of showing them.
  SubscriptionHealth _healthOf(SubscriptionUserInfo? info, DateTime now) {
    if (info == null) {
      return SubscriptionHealth.ok;
    }
    if (info.isExpiredAt(now)) {
      return SubscriptionHealth.error;
    }
    if (info.isNearQuota || info.isExpiringAt(now)) {
      return SubscriptionHealth.warning;
    }
    return SubscriptionHealth.ok;
  }

  List<SubscriptionCardLink> _links(Translations t) {
    final support = subscription.supportUrl;
    final site = subscription.profileWebPageUrl;
    return <SubscriptionCardLink>[
      if (support != null)
        SubscriptionCardLink(
          label: t.subscription.support,
          icon: CommyIcons.externalLink,
          onPressed: () => unawaited(_open(support)),
        ),
      if (site != null)
        SubscriptionCardLink(
          label: t.subscription.website,
          icon: CommyIcons.globe,
          onPressed: () => unawaited(_open(site)),
        ),
    ];
  }

  /// Opens a link the **panel** supplied, in the system browser.
  ///
  /// Rule R1 holds: this is not a request Commy makes, it is a link the user
  /// taps, handed to another application.
  Future<void> _open(Uri url) async {
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
