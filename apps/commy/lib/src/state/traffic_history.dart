import 'dart:collection';

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
