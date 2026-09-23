import 'dart:async';

import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/i18n/relative_time.dart';
import 'package:commy/src/i18n/translations_locale.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/screens/home/widgets/measure_progress_row.dart';
import 'package:commy/src/screens/home/widgets/node_row.dart';
import 'package:commy/src/screens/home/widgets/panel_notice_row.dart';
import 'package:commy/src/screens/home/widgets/subscription_menu_sheet.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/settings_controller.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
    final activeId = ref.watch(activeNodeIdProvider);
    final busy = ref.watch(subscriptionControllerProvider);
    final measuring = ref.watch(measurementProvider);
    final isMeasuringThis = measuring.scopeId == subscription.id;
    final info = subscription.userInfo;
    final notices =
        ref.watch(panelNoticesProvider)[subscription.id] ?? const <String>[];
    final deviceIdOff =
        ref.watch(settingsProvider).value?.sendDeviceId == false;
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
      onRefresh: () => unawaited(_refresh(context, ref, t)),
      // No servers, no button. A panel that answered with nothing — refused,
      // or empty — left a card whose "measure all" was enabled and did
      // nothing at all when pressed: no probe, no progress row, no message.
      // Disabling it instead of hiding it would have been worse: a disabled
      // icon is `textDisabled`, which in the light theme is 2:1 against the
      // card and reads as a smudge rather than as a control.
      onPingAll: nodes.isEmpty
          ? null
          : () => unawaited(
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
        // Above the servers, because when it is there they are usually not:
        // a panel that answers with a notice answers with nothing else.
        if (notices.isNotEmpty)
          PanelNoticeRow(
            messages: notices,
            onSendDeviceId: deviceIdOff
                ? () => unawaited(_sendDeviceIdAndRefresh(context, ref, t))
                : null,
          ),
        // And when it answered with neither servers nor a word about it, the
        // card used to be a name and a blank: no rows, no explanation, and a
        // person left to wonder whether the app lost their servers. One
        // quiet line, and deliberately a factual one — a panel may be empty
        // for an hour of maintenance, so "no servers yet" is all that is
        // actually known. The way out is the refresh two icons up.
        if (nodes.isEmpty && notices.isEmpty) const _NoServersRow(),
        if (isMeasuringThis) const MeasureProgressRow(),
        for (final node in nodes)
          NodeRow(node: node, isActive: node.id == activeId),
      ],
    );
  }

  /// Refreshes the panel, and says how it went — either way.
  ///
  /// The call used to be fired and forgotten: the spinner stopped, the card
  /// kept its old "2 hours ago", and a panel that refused — expired, revoked,
  /// over its device limit, all of them a 403 — looked exactly like a panel
  /// that had nothing new. The refresh button is pressed more often than
  /// anything else on this screen, so it is the worst place to stay quiet.
  ///
  /// The sentence comes from [FailureText] here, unlike on the rule sets
  /// screen: this really is a subscription, so "the subscription server is
  /// not answering" — or, for a status, "the panel refused: HTTP 403" — is
  /// the truth rather than a borrowed line.
  Future<void> _refresh(
    BuildContext context,
    WidgetRef ref,
    Translations t,
  ) async {
    final ok = await ref
        .read(subscriptionControllerProvider.notifier)
        .refresh(subscription.id);
    if (!context.mounted) {
      return;
    }
    if (ok) {
      // Success says so too. The card's "just now" was the only sign, and
      // it is the line nobody reads — the owner kept pressing refresh to see
      // whether anything had happened.
      ToastMessenger.show(
        context,
        message: t.subscription.refreshed(
          count: ref.read(subscriptionControllerProvider).importedCount ?? 0,
        ),
        tone: CommyTone.connected,
        icon: CommyIcons.success,
      );
      return;
    }
    final failure = ref.read(subscriptionControllerProvider).failure;
    if (failure == null) {
      // Declined because another refresh is already running. Nothing broke.
      return;
    }
    ToastMessenger.show(
      context,
      message: FailureText.of(failure, t).message,
      tone: CommyTone.error,
      icon: CommyIcons.warning,
      actionLabel: t.error.openLogs,
      onAction: () => context.go(AppRoutes.diagnosticsLogs),
    );
  }

  /// Turns the device identifier back on and asks the panel again, which is
  /// the whole fix for "App not supported" from a panel that limits devices.
  Future<void> _sendDeviceIdAndRefresh(
    BuildContext context,
    WidgetRef ref,
    Translations t,
  ) async {
    await ref
        .read(settingsControllerProvider.notifier)
        .setSendDeviceId(enabled: true);
    if (!context.mounted) {
      return;
    }
    await _refresh(context, ref, t);
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
      // No ceiling to draw a bar against, but the panel still said how much
      // went through, and that is the one number an unlimited plan has. The
      // bare word alone read as a stray caption under the card's header.
      return used > 0
          ? t.subscription.usedUnlimited(
              used: CommyByteFormat.bytes(used, locale: t.flutterLocale),
            )
          : t.subscription.unlimited;
    }
    return t.subscription.quota(
      used: CommyByteFormat.bytes(used, locale: t.flutterLocale),
      total: CommyByteFormat.bytes(total, locale: t.flutterLocale),
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
      used: CommyByteFormat.bytes(used, locale: t.flutterLocale),
      total: CommyByteFormat.bytes(total, locale: t.flutterLocale),
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

/// The one line a subscription with nothing in it gets.
class _NoServersRow extends StatelessWidget {
  const _NoServersRow();

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final colors = context.colors;
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.s4,
        vertical: spacing.s3,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            CommyIcons.info,
            size: CommySizes.iconControl,
            color: colors.textTertiary,
          ),
          SizedBox(width: spacing.s3),
          Expanded(
            child: Text(
              t.subscription.noServers,
              style: context.typography.body.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
