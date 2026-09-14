import 'package:commy_domain/src/core/failure.dart';
import 'package:commy_domain/src/core/result.dart';
import 'package:commy_domain/src/entities/traffic_day.dart';
import 'package:commy_domain/src/entities/traffic_sample.dart';

/// Daily traffic totals, for the statistics screen.
///
/// The core reports cumulative counters that start over every time the tunnel
/// comes up, so what an implementation keeps are *deltas* between consecutive
/// samples, added to the bucket of the day they arrived in.
abstract interface class TrafficHistoryRepository {
  /// Adds the difference between [sample] and the previous one.
  ///
  /// [scope] is a node id, or [TrafficDay.allScope] for the unattributed
  /// total. Call it with every tick the core emits; the first tick after
  /// [resetSession] only establishes the baseline and stores nothing.
  Future<Result<void, CommyFailure>> recordSample(
    TrafficSample sample, {
    String scope = TrafficDay.allScope,
  });

  /// Forgets the baseline. Call it when the tunnel goes down, so the first
  /// sample of the next session is not read as a change from the last one.
  void resetSession();

  /// The days from [from] to [to] inclusive, oldest first, once.
  Future<Result<List<TrafficDay>, CommyFailure>> readRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  });

  /// The days from [from] to [to] inclusive, oldest first, refreshed on every
  /// change.
  Stream<List<TrafficDay>> watchRange({
    required DateTime from,
    required DateTime to,
    String scope = TrafficDay.allScope,
  });

  /// Drops every recorded day.
  Future<Result<void, CommyFailure>> clear();
}
