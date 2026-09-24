import 'package:commy/gen/strings.g.dart';
import 'package:commy/src/i18n/failure_text.dart';
import 'package:commy/src/router/app_router.dart';
import 'package:commy/src/router/app_routes.dart';
import 'package:commy/src/state/auto_refresh_notice.dart';
import 'package:commy/src/state/measurement_controller.dart';
import 'package:commy/src/state/measurement_report.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy/src/widgets/toast_messenger.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shows the one-line results the tunnel produces, wherever the user is.
///
/// `TunnelController` stores a handful of them — the reachability probe
/// passed, with or without the exit address; the probe failed; the IP check
/// did not answer; the outbound was switched; a changed configuration was
/// applied — and before this existed each one was written to state and read
/// by nobody: pressing «Проверить» ran a real probe through the core and then
/// said nothing at all.
///
/// The same goes for the two other producers with no screen of their own: a
/// latency measurement, whose answer used to be a figure changing somewhere
/// down the list, and the automatic subscription refresh, which runs from the
/// root on a timer.
///
/// It sits in `MaterialApp.builder` rather than on the home screen because a
/// node switch can be triggered from anywhere the list is shown, and a result
/// that only appears on one route is a result the user misses.
class NoticeHost extends ConsumerStatefulWidget {
  /// Wraps [child].
  const NoticeHost({required this.child, super.key});

  /// The navigator below.
  final Widget child;

  @override
  ConsumerState<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends ConsumerState<NoticeHost> {
  @override
  Widget build(BuildContext context) {
    ref
      ..listen<TunnelActionState>(tunnelControllerProvider, (previous, next) {
        final notice = next.notice;
        if (notice == null || notice == previous?.notice) {
          return;
        }
        _show(notice);
      })
      // A run of latency probes has no screen of its own to fail on: the
      // progress row is gone by the time the last one comes back. Without
      // this, "Latency probe URL is not configured" was written to state and
      // read by nobody, and the run just looked like it did nothing.
      ..listen<MeasurementState>(measurementProvider, (previous, next) {
        // Only a report this change brought; one already said is not news.
        final report = next.report == previous?.report ? null : next.report;
        // A failure is said instead of the numbers only when the numbers
        // have nothing to say — nobody answered, or there was no run to
        // count. A run the failure broke outright, the probe URL missing, is
        // one where every server failed. One server of seventeen that could
        // not be measured — a panel's mKCP node the core does not carry, so
        // no probe can be built for it — must not swallow what the other
        // sixteen found; the report counts it with the ones that did not
        // answer.
        final answered = (report?.reachable ?? 0) > 0;
        final failure = next.failure;
        if (failure != null && failure != previous?.failure && !answered) {
          _showFailure(failure);
          return;
        }
        // One toast per finished measurement, skipped servers included, so
        // two toasts about the same run do not overwrite each other.
        if (report != null) {
          _showReport(report);
          return;
        }
        // Nothing was measured at all — every server was on UDP, with the
        // TCP method. The long form, since it says what would measure them.
        final skipped = next.skipped;
        if (skipped > 0 && skipped != previous?.skipped) {
          _showSkipped(skipped);
        }
      })
      ..listen<AutoRefreshNotice?>(autoRefreshNoticeProvider, (previous, next) {
        if (next != null && next != previous) {
          _showAutoRefresh(next);
        }
      });
    return widget.child;
  }

  void _showFailure(CommyFailure failure) {
    final text = FailureText.of(failure, Translations.of(context));
    ToastMessenger.show(
      context,
      message: text.message,
      tone: CommyTone.error,
      icon: CommyIcons.warning,
    );
    ref.read(measurementProvider.notifier).clearOutcome();
  }

  void _showSkipped(int count) {
    ToastMessenger.show(
      context,
      message: Translations.of(context).home.measureSkippedUdp(count: count),
      tone: CommyTone.info,
      icon: CommyIcons.diagnostics,
    );
    ref.read(measurementProvider.notifier).clearOutcome();
  }

  /// `Отвечают 15 из 17 · лучший — Finland, 90 мс · 2 UDP пропущены`, or the
  /// one server by name.
  ///
  /// Short on purpose: a toast on a 360 dp phone has room for about sixty
  /// characters in two lines, and that sentence is two lines there — pinned
  /// by `notice_fit_test.dart`, in the real font. A longer server name takes
  /// it to a third; the parts that are always there are what is kept short.
  /// The method is left out — it is a setting the user chose — and so is a
  /// "Ping:" lead: the user has just pressed the button and watched the
  /// counter. "UDP", not "UDP-сервера": the list around the toast already
  /// says what they are.
  void _showReport(MeasurementReport report) {
    final ping = Translations.of(context).home.ping;
    final node = report.node;
    final latency = report.latency;
    final name = node == null ? '' : NodeLabel.of(node).text;
    final answered = report.reachable > 0;
    final parts = <String>[
      if (report.isSingle)
        latency == null
            ? ping.singleSilent(name: name)
            : ping.single(name: name, ms: latency.inMilliseconds)
      else if (!answered)
        ping.noneAnswered(count: report.measured)
      else ...<String>[
        ping.summary(count: report.reachable, total: report.measured),
        if (node != null && latency != null)
          ping.best(name: name, ms: latency.inMilliseconds),
      ],
      if (report.skipped > 0) ping.skipped(count: report.skipped),
    ];
    ToastMessenger.show(
      context,
      message: parts.join(NodeTile.descriptorSeparator),
      tone: answered ? CommyTone.connected : CommyTone.error,
      icon: answered ? CommyIcons.success : CommyIcons.offline,
    );
    ref.read(measurementProvider.notifier).clearOutcome();
  }

  /// A refresh nobody pressed for, so it names the subscription.
  ///
  /// A failure is a headline and a way to the logs, not the reason: on a
  /// 360 dp phone the full explanation of a panel's 403 ran to eleven lines
  /// over the app bar, for something the user did not ask for. Two lines,
  /// pinned by `notice_fit_test.dart`. The reason is in the log line the
  /// scheduler writes, and a refresh from the card says it in full.
  void _showAutoRefresh(AutoRefreshNotice notice) {
    final t = Translations.of(context);
    if (notice.failure == null) {
      ToastMessenger.show(
        context,
        message: t.subscription.autoRefreshed(
          name: notice.name,
          nodes: t.subscription.nodes(count: notice.count ?? 0),
        ),
        tone: CommyTone.connected,
        icon: CommyIcons.refresh,
      );
    } else {
      ToastMessenger.show(
        context,
        message: t.subscription.autoRefreshFailed(name: notice.name),
        tone: CommyTone.error,
        icon: CommyIcons.warning,
        // The tab's name, not «Открыть логи»: beside the longer label the
        // sentence had a third of the toast's width, and took three lines.
        actionLabel: t.diagnostics.logs,
        // Above the router, so not `context.go`: there is no `GoRouter` in
        // this widget's ancestry, only in the provider it came from.
        onAction: () => ref.read(routerProvider).go(AppRoutes.diagnosticsLogs),
      );
    }
    ref.read(autoRefreshNoticeProvider.notifier).clear();
  }

  void _show(TunnelNotice notice) {
    final t = Translations.of(context);
    final ms = notice.milliseconds ?? 0;
    final ip = notice.name;
    final (String message, CommyTone tone, IconData icon) =
        switch (notice.kind) {
      TunnelNoticeKind.checkPassed => (
          ip == null
              ? t.home.checkOk(ms: ms)
              : t.home.checkOkWithIp(ms: ms, ip: ip),
          CommyTone.connected,
          CommyIcons.success,
        ),
      TunnelNoticeKind.checkFailed => (
          t.home.checkFailed,
          CommyTone.error,
          CommyIcons.warning,
        ),
      TunnelNoticeKind.switched => (
          t.home.switched(name: notice.name ?? ''),
          CommyTone.info,
          CommyIcons.proxy,
        ),
      TunnelNoticeKind.switchedToAuto => (
          t.home.switchedToAuto,
          CommyTone.info,
          CommyIcons.proxy,
        ),
      TunnelNoticeKind.reloaded => (
          t.home.settingsApplied,
          CommyTone.info,
          CommyIcons.refresh,
        ),
      TunnelNoticeKind.ipCheckFailed => (
          t.home.ipCheckFailed(ms: ms),
          CommyTone.error,
          CommyIcons.warning,
        ),
    };

    ToastMessenger.show(context, message: message, tone: tone, icon: icon);
    ref.read(tunnelControllerProvider.notifier).clearNotice();
  }
}
