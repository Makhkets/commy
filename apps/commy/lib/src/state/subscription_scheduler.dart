import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/auto_refresh_notice.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/subscription_controller.dart';
import 'package:commy_data/commy_data.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs the automatic refresh the subscription card has been promising.
///
/// The card said `авто 1 ч` from the first release and nothing ever ran: the
/// flag was stored, the interval was stored, and no timer read either. This
/// provider is the timer. Watched once from the root widget, so a refresh due
/// while the user is on the settings screen still happens.
final subscriptionRefreshProvider = Provider<SubscriptionScheduler>((ref) {
  final scheduler = SubscriptionScheduler(ref);
  final timer = Timer.periodic(
    SubscriptionScheduler.tick,
    (_) => unawaited(scheduler.sweep()),
  );
  // A sweep as soon as the stored list arrives, and after every edit: a
  // subscription that fell due while the app was closed must not sit there
  // until the first tick, and switching auto refresh on should mean something
  // before the next minute is up.
  //
  // Deliberately not `fireImmediately`. That callback runs inside this
  // provider's own build, and a sweep starts writing to
  // `subscriptionControllerProvider` before its first await — which Riverpod
  // refuses, and rightly. The root widget watches this provider at startup,
  // long before the repository stream has produced anything, so the first
  // emission is the initial sweep.
  ref
    ..listen<AsyncValue<List<Subscription>>>(
      subscriptionsProvider,
      (previous, next) {
        if (next.hasValue) {
          unawaited(scheduler.sweep());
        }
      },
    )
    ..onDispose(timer.cancel);
  return scheduler;
});

/// The wall clock the schedule is measured against.
///
/// Deliberately not `clockProvider`: that is a one-second ticker for the
/// session timer and connection ages, and its value is null until a screen
/// listens to it — a schedule that read it would quietly change its mind
/// about the time depending on which screen was open. Overridden in tests,
/// which is the only reason it is a provider at all.
final refreshClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Decides which subscriptions are due and refreshes them, one at a time.
class SubscriptionScheduler {
  /// Creates the scheduler over [_ref].
  SubscriptionScheduler(this._ref);

  /// How often the due list is re-examined.
  ///
  /// A minute against intervals measured in hours: fine enough that a refresh
  /// is never visibly late, coarse enough to cost nothing.
  static const Duration tick = Duration(minutes: 1);

  /// How long a subscription is left alone after a failed refresh.
  ///
  /// Without this a panel that is down would be asked once a tick forever,
  /// which is both useless and rude to a server that is already struggling.
  /// The wait is not persisted: a restart is the user asking again.
  static const Duration retryAfterFailure = Duration(minutes: 15);

  /// Tag on the log lines this scheduler writes.
  static const String logTag = 'subscription.auto';

  final Ref _ref;
  final Map<String, DateTime> _notBefore = <String, DateTime>{};

  /// Subscriptions whose automatic refresh is failing, each with the
  /// `lastUpdatedAt` it had when the failures began.
  ///
  /// A failure is announced once per streak — the first one after a refresh
  /// that worked, or after the app started — and not on every retry: a
  /// panel that is down for an afternoon would otherwise say so every
  /// fifteen minutes, over whatever the user was doing. The card shows no
  /// failure of its own, so without the first one nothing would.
  final Map<String, DateTime?> _failingSince = <String, DateTime?>{};

  /// Whether the current sweep has already said that a refresh failed.
  ///
  /// Toasts replace each other rather than queue, so the next subscription's
  /// "refreshed" took a failure down as soon as its own download came back —
  /// and the streak rule then kept that failure quiet on every retry, so it
  /// was never seen at all. At a cold start after a long pause every
  /// subscription is due at once, which makes that the usual case. Within one
  /// sweep a failure outranks a success, and a second failure waits for its
  /// own retry rather than covering the first.
  bool _failureSaid = false;
  bool _sweeping = false;

  /// Refreshes every subscription that is due, sequentially.
  ///
  /// Sequential because `SubscriptionController.refresh` serves one at a time
  /// anyway — a parallel sweep would silently drop every subscription but the
  /// first, which is the worst of both.
  Future<void> sweep() async {
    if (_sweeping) {
      return;
    }
    _sweeping = true;
    _failureSaid = false;
    try {
      final items =
          _ref.read(subscriptionsProvider).value ?? const <Subscription>[];
      for (final item in items) {
        final now = _now();
        if (!item.isRefreshDueAt(now) || _isCoolingDown(item.id, now)) {
          continue;
        }
        await _refresh(item, now);
      }
    } finally {
      _sweeping = false;
    }
  }

  Future<void> _refresh(Subscription item, DateTime now) async {
    final controller = _ref.read(subscriptionControllerProvider.notifier);
    if (await controller.refresh(item.id)) {
      _notBefore.remove(item.id);
      _failingSince.remove(item.id);
      final count =
          _ref.read(subscriptionControllerProvider).importedCount ?? 0;
      if (!_failureSaid) {
        _notices.refreshed(name: await _nameOf(item), count: count);
      }
      return;
    }
    final failure = _ref.read(subscriptionControllerProvider).failure;
    if (failure == null) {
      // Declined because a manual refresh is already running. Nothing went
      // wrong, so nothing is recorded — the next tick will find it again.
      return;
    }
    _notBefore[item.id] = now.add(retryAfterFailure);
    // Not recorded as said unless it was: a failure held back behind
    // another one of this sweep is news on its next retry.
    if (!_failureSaid && _startsStreak(item)) {
      _failingSince[item.id] = item.lastUpdatedAt;
      _failureSaid = true;
      _notices.failed(name: item.name, failure: failure);
    }
    // The id, not the URL: the URL carries the access token (rule R3).
    _ref.read(appLoggerProvider).warn(
          'automatic refresh of ${item.id} failed: ${_describe(failure)}; '
          'not retrying for ${retryAfterFailure.inMinutes} min',
          tag: logTag,
        );
  }

  /// The failure's code, and what the panel's HTTP exchange said when that
  /// is what went wrong — `subscription_unreachable (status 403)`.
  ///
  /// The toast is a headline that sends the user here, so this line is where
  /// the reason has to be. A status and a kind carry no token (rule R3).
  static String _describe(CommyFailure failure) {
    if (failure
        case SubscriptionUnreachableFailure(
          cause: HttpTransportError(:final kind, :final statusCode),
        )) {
      final status = statusCode == null ? '' : ' $statusCode';
      return '${failure.code} ($kind$status)';
    }
    return failure.code;
  }

  /// Whether a failure of [item] is the first since it last refreshed.
  ///
  /// A `lastUpdatedAt` that moved since the streak began means a refresh
  /// worked in between — the user's own, from the card, which this
  /// scheduler never sees — and a new failure after it is news again.
  bool _startsStreak(Subscription item) =>
      !_failingSince.containsKey(item.id) ||
      _failingSince[item.id] != item.lastUpdatedAt;

  /// The name as the card shows it once the refresh landed: a panel may
  /// send a new title with its servers.
  Future<String> _nameOf(Subscription item) async {
    final stored =
        await _ref.read(subscriptionRepositoryProvider).findById(item.id);
    return stored.valueOrNull?.name ?? item.name;
  }

  AutoRefreshNotices get _notices =>
      _ref.read(autoRefreshNoticeProvider.notifier);

  bool _isCoolingDown(String id, DateTime now) {
    final until = _notBefore[id];
    return until != null && now.isBefore(until);
  }

  DateTime _now() => _ref.read(refreshClockProvider)();
}
