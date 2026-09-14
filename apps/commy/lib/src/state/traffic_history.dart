import 'dart:async';
import 'dart:collection';

import 'package:commy/src/di/infrastructure_providers.dart';
import 'package:commy/src/di/repository_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:commy_ui/commy_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The last sixty seconds of throughput, kept in memory.
///
/// A ring rather than a growing list: the chart draws a fixed window, so
/// anything older is not "history", it is a leak that grows for as long as the
/// tunnel is up.
final trafficHistoryProvider =
    NotifierProvider<TrafficHistory, TrafficWindow>(TrafficHistory.new);

/// A snapshot of the window.
@immutable
class TrafficWindow {
  /// Creates the snapshot.
  const TrafficWindow(this.samples);

  /// Nothing recorded yet.
  static const TrafficWindow empty = TrafficWindow(<TrafficSample>[]);

  /// Oldest first.
  final List<TrafficSample> samples;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficWindow && listEquals(other.samples, samples);

  @override
  int get hashCode => Object.hashAll(samples);

  @override
  String toString() => 'TrafficWindow(${samples.length} samples)';
}

/// Collects traffic samples into a bounded window.
class TrafficHistory extends Notifier<TrafficWindow> {
  /// How many samples the window holds.
  ///
  /// The core sends one a second and the chart shows
  /// `CommyThresholds.chartWindow`, so this is that window plus a couple of
  /// samples of slack for a late tick.
  static const int capacity = 64;

  final ListQueue<TrafficSample> _samples = ListQueue<TrafficSample>();

  @override
  TrafficWindow build() {
    ref.listen<AsyncValue<TrafficSample>>(
      trafficProvider,
      (previous, next) {
        final sample = next.value;
        if (sample != null) {
          _add(sample);
        }
      },
      fireImmediately: true,
    );
    return TrafficWindow.empty;
  }

  void _add(TrafficSample sample) {
    _samples.addLast(sample);
    while (_samples.length > capacity) {
      _samples.removeFirst();
    }
    state = TrafficWindow(List<TrafficSample>.unmodifiable(_samples));
  }

  /// The window the chart draws, for tests and for the widget alike.
  static Duration get window => CommyThresholds.chartWindow;
}

const String _tag = 'traffic';

/// Writes what the tunnel carries into the daily totals.
///
/// Watched from the root like the log pump: recording must not depend on the
/// statistics screen ever having been opened. The store keeps a baseline
/// between samples, and the baseline is dropped when the tunnel goes down so
/// the first sample of the next session is not read as a change from the
/// last one of the previous.
final trafficHistoryPumpProvider = Provider<void>((ref) {
  final repository = ref.watch(trafficHistoryRepositoryProvider);
  final logger = ref.watch(appLoggerProvider);
  // Once, not once a second: a database that refused one write will refuse
  // the next, and the log has better things to hold.
  var warned = false;

  ref
    ..listen<AsyncValue<TrafficSample>>(trafficProvider, (previous, next) {
      final sample = next.value;
      if (sample == null) {
        return;
      }
      unawaited(
        repository.recordSample(sample).then((result) {
          final failure = result.failureOrNull;
          if (failure != null && !warned) {
            warned = true;
            logger.warn(
              'traffic history write failed: ${failure.code}',
              tag: _tag,
            );
          }
        }),
      );
    })
    ..listen<AsyncValue<TunnelStatus>>(coreStatusProvider, (previous, next) {
      switch (next.value) {
        case TunnelIdle() || TunnelError():
          repository.resetSession();
        case TunnelStarting() ||
              TunnelConnected() ||
              TunnelChecking() ||
              TunnelStopping() ||
              null:
          break;
      }
    });
});

/// How many days the statistics screen lists.
const int trafficDaysShown = 7;

/// The last [trafficDaysShown] days of totals, oldest first.
///
/// Keyed on the *day* of the clock, not on its every tick: the database watch
/// is re-opened at midnight, not once a second. Auto-disposed, so a visit to
/// the screen tomorrow asks for tomorrow's week.
final StreamProvider<List<TrafficDay>> trafficDaysProvider =
    StreamProvider.autoDispose((ref) {
  final today = ref.watch(
    clockProvider.select((clock) => _dayOf(clock.value ?? DateTime.now())),
  );
  return ref.watch(trafficHistoryRepositoryProvider).watchRange(
        // Arithmetic on the day number, not a Duration: across a daylight
        // saving change six times 24 hours is not six days.
        from:
            DateTime(today.year, today.month, today.day - trafficDaysShown + 1),
        to: today,
      );
});

DateTime _dayOf(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);
