import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Measuring a whole list of servers: how far it has got, and stopping it.
///
/// `TunnelController.measure` still probes one node — that is a single tap
/// with nothing to report beyond the number it writes. A run over thirty
/// servers is a different thing: it takes long enough that the user needs to
/// see it moving and long enough that they need to be able to call it off.
final measurementProvider =
    NotifierProvider<MeasurementController, MeasurementState>(
  MeasurementController.new,
);

/// How far the current run has got, if there is one.
@immutable
class MeasurementState {
  /// Creates the state.
  const MeasurementState({
    this.scopeId,
    this.done = 0,
    this.total = 0,
    this.failure,
  });

  /// Nothing is being measured.
  static const MeasurementState idle = MeasurementState();

  /// Which list is being measured, so one card's progress does not appear
  /// under another. `null` when nothing is running.
  final String? scopeId;

  /// How many servers have been probed so far.
  final int done;

  /// How many were asked for.
  final int total;

  /// What the last probe failed with. A timeout is not a failure — the use
  /// case reports that as a measurement of `null`.
  final CommyFailure? failure;

  /// Whether a run is in progress.
  bool get isRunning => scopeId != null;

  /// Share of the run that is finished, in `0..1`.
  double get ratio => total == 0 ? 0 : done / total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementState &&
          other.scopeId == scopeId &&
          other.done == done &&
          other.total == total &&
          other.failure == failure;

  @override
  int get hashCode => Object.hash(scopeId, done, total, failure);

  @override
  String toString() => 'MeasurementState($scopeId, $done/$total, $failure)';
}

/// Runs a batch of latency probes and reports on it.
class MeasurementController extends Notifier<MeasurementState> {
  /// How many probes are in flight at once.
  ///
  /// Not one, and not thirty. Sequential made a subscription of thirty
  /// servers take half a minute; all at once measures the tunnel's own queue
  /// rather than the servers, which is the reason the old code was
  /// sequential in the first place. Four is small enough that the queue is
  /// never the thing being timed.
  static const int batchSize = 4;

  @override
  MeasurementState build() => MeasurementState.idle;

  /// The run that is currently allowed to continue.
  ///
  /// Bumped by [cancel] and by every new run, so a batch that finishes after
  /// its run was called off writes no progress and starts nothing further.
  int _generation = 0;

  /// Probes every node in [nodes], [batchSize] at a time.
  ///
  /// [scopeId] names the list on screen — a subscription id — so the card
  /// that started the run is the one that shows it.
  ///
  /// Does nothing while another run is going: two runs would fight over the
  /// same counter and neither number would mean anything.
  Future<void> measureAll(
    List<ProxyNode> nodes, {
    required String scopeId,
  }) async {
    if (state.isRunning || nodes.isEmpty) {
      return;
    }
    final generation = ++_generation;
    state = MeasurementState(scopeId: scopeId, total: nodes.length);

    for (var start = 0; start < nodes.length; start += batchSize) {
      if (generation != _generation) {
        return;
      }
      final end = (start + batchSize).clamp(0, nodes.length);
      final batch = nodes.sublist(start, end);
      final failures = await Future.wait(batch.map(_measure));
      if (generation != _generation) {
        return;
      }
      state = MeasurementState(
        scopeId: scopeId,
        done: end,
        total: nodes.length,
        // The last thing that went wrong, not the first: the freshest
        // failure is the one worth putting in front of the user.
        failure: failures.nonNulls.lastOrNull ?? state.failure,
      );
    }
    state = MeasurementState(failure: state.failure);
  }

  /// Stops the run. Probes already in flight finish and their numbers are
  /// kept — a measurement that came back is still true.
  void cancel() {
    if (!state.isRunning) {
      return;
    }
    _generation++;
    state = MeasurementState(failure: state.failure);
  }

  /// Drops the last failure once it has been shown.
  void clearFailure() => state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
      );

  Future<CommyFailure?> _measure(ProxyNode node) async {
    final result = await ref.read(measureLatencyUseCaseProvider)(
      nodeId: node.id,
      outboundTag: SingBoxTags.forNode(node),
    );
    return result.failureOrNull;
  }
}
