import 'dart:async';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/rule_set_controller.dart';
import 'package:commy/src/state/subscription_scheduler.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keeps rule sets fresh on the interval the user chose — and only then.
///
/// Exceptions E-2 and E-3 (docs/09) allow a refresh "on an interval the user
/// sets, off by default". So this does nothing at all until
/// `AppSettings.ruleSetUpdateDays` is set, and even then it only fetches
/// again what is already on disk *and* what the current rules need: a timer
/// never downloads a rule set for the first time, and never keeps one
/// nobody uses up to date. The request is the button's own — same source,
/// same repository, same atomic replace.
///
/// Watched from the root. Hourly, because the intervals are days; and on
/// every change of the settings or the files, so switching it on means
/// something before the hour is up.
final ruleSetRefreshProvider = Provider<RuleSetScheduler>((ref) {
  final scheduler = RuleSetScheduler(ref);
  final timer = Timer.periodic(
    RuleSetScheduler.tick,
    (_) => unawaited(scheduler.sweep()),
  );
  // Not `fireImmediately`, for the reason subscriptionRefreshProvider gives:
  // a sweep writes to a notifier, which Riverpod refuses inside this build.
  ref
    ..listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      if (next.hasValue) {
        unawaited(scheduler.sweep());
      }
    })
    ..onDispose(timer.cancel);
  return scheduler;
});

/// See [ruleSetRefreshProvider].
class RuleSetScheduler {
  /// Creates the scheduler.
  RuleSetScheduler(this._ref);

  /// How often the files are looked at.
  static const Duration tick = Duration(hours: 1);

  /// How long a source that failed is left alone. Hours, not minutes: the
  /// file on disk still works, and a mirror that is down is not helped by
  /// being asked every tick.
  static const Duration retryAfterFailure = Duration(hours: 6);

  /// Tag of this scheduler's log lines.
  static const String logTag = 'rulesets.auto';

  final Ref _ref;
  final Map<String, DateTime> _notBefore = <String, DateTime>{};
  bool _sweeping = false;

  /// Refreshes every rule set that is due.
  Future<void> sweep() async {
    if (_sweeping) {
      return;
    }
    _sweeping = true;
    try {
      final settings = _ref.read(settingsProvider).value;
      if (settings == null || !settings.isRuleSetAutoUpdateEnabled) {
        return;
      }
      final every = Duration(days: settings.ruleSetUpdateDays);
      for (final set in _due(every)) {
        await _refresh(set.tag);
      }
    } finally {
      _sweeping = false;
    }
  }

  List<RuleSet> _due(Duration every) {
    final policy = _ref.read(routingPolicyProvider).value;
    if (policy == null) {
      return const <RuleSet>[];
    }
    final needed = RouteSectionBuilder.requiredRuleSets(
      routing: policy,
      platform: _ref.read(configPlatformProvider),
    ).toSet();
    final now = _now();
    return <RuleSet>[
      for (final set in _ref.read(ruleSetsProvider).value ?? const <RuleSet>[])
        if (needed.contains(set.tag) &&
            now.difference(set.updatedAt) >= every &&
            !_isCoolingDown(set.tag, now))
          set,
    ];
  }

  Future<void> _refresh(String tag) async {
    final controller = _ref.read(ruleSetControllerProvider.notifier);
    final logger = _ref.read(appLoggerProvider);
    if (await controller.download(tag)) {
      _notBefore.remove(tag);
      logger.info('refreshed rule set $tag', tag: logTag);
      return;
    }
    final failure = _ref.read(ruleSetControllerProvider).failure;
    if (failure == null) {
      // Declined: a download from the screen is running, or the source was
      // just cleared. Nothing failed; the next sweep looks again.
      return;
    }
    _notBefore[tag] = _now().add(retryAfterFailure);
    // The tag and the code, not the URL: rule R3 keeps full URLs out of the
    // log, even a public mirror's.
    logger.warn(
      'refreshing rule set $tag failed: ${failure.code}; '
      'not retrying for ${retryAfterFailure.inHours} h',
      tag: logTag,
    );
  }

  bool _isCoolingDown(String tag, DateTime now) {
    final until = _notBefore[tag];
    return until != null && now.isBefore(until);
  }

  DateTime _now() => _ref.read(refreshClockProvider)();
}
