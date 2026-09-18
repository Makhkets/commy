import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/tunnel_controller.dart';
import 'package:commy_config/commy_config.dart';
import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Measuring servers: one, or a whole list with progress and a way to stop.
///
/// Both live here, and neither touches `TunnelController`. The single probe
/// used to, and wrote its failure into the tunnel's state — so a ping that
/// went wrong painted the connect button red and put "something went wrong"
/// under it, on a tunnel that was never asked to do anything. A measurement
/// that fails is a toast about a measurement.
///
/// With the tunnel up the core does the measuring; with it down the app times
/// the server's TCP handshake itself — see `MeasureLatencyUseCase`. Which one
/// applies is decided once per run, so the numbers inside one run are always
/// comparable.
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
    this.needTunnel = 0,
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

  /// How many servers the last run left alone because they can only be
  /// measured through a running tunnel — UDP protocols, with the tunnel down.
  ///
  /// Reported rather than dropped: a run that silently skips three rows looks
  /// exactly like a run that broke on them.
  final int needTunnel;

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
          other.failure == failure &&
          other.needTunnel == needTunnel;

  @override
  int get hashCode => Object.hash(scopeId, done, total, failure, needTunnel);

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

  /// Probes one server, for the "measure" row of its menu.
  ///
  /// No progress to show — the number landing on the row is the report — but
  /// the same rules as a run: a failure is this controller's to announce, and
  /// a server that needs the tunnel says so instead of failing.
  Future<void> measureOne(ProxyNode node) async {
    final throughCore = _isTunnelUp;
    if (!throughCore && !MeasureLatencyUseCase.isDirectlyMeasurable(node)) {
      state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
        needTunnel: 1,
      );
      return;
    }
    final failure = await _measure(node, throughCore: throughCore);
    if (failure != null) {
      state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
        failure: failure,
      );
    }
  }

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
    // Decided once, so every number in the run was taken the same way. A
    // tunnel that comes up halfway through does not switch the method on the
    // rows that are left.
    final throughCore = _isTunnelUp;
    final measurable = throughCore
        ? nodes
        : <ProxyNode>[
            for (final node in nodes)
              if (MeasureLatencyUseCase.isDirectlyMeasurable(node)) node,
          ];
    final needTunnel = nodes.length - measurable.length;
    if (measurable.isEmpty) {
      state = MeasurementState(needTunnel: needTunnel);
      return;
    }

    final generation = ++_generation;
    state = MeasurementState(scopeId: scopeId, total: measurable.length);

    for (var start = 0; start < measurable.length; start += batchSize) {
      if (generation != _generation) {
        return;
      }
      final end = (start + batchSize).clamp(0, measurable.length);
      final batch = measurable.sublist(start, end);
      final failures = await Future.wait(
        batch.map((node) => _measure(node, throughCore: throughCore)),
      );
      if (generation != _generation) {
        return;
      }
      state = MeasurementState(
        scopeId: scopeId,
        done: end,
        total: measurable.length,
        // The last thing that went wrong, not the first: the freshest
        // failure is the one worth putting in front of the user.
        failure: failures.nonNulls.lastOrNull ?? state.failure,
      );
    }
    state = MeasurementState(failure: state.failure, needTunnel: needTunnel);
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

  /// Drops the last failure, and the "needs the tunnel" count, once shown.
  void clearFailure() => state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
      );

  /// Whether the core is up to measure through.
  ///
  /// The core's own word, not the button's: `tunnelStatusProvider` folds local
  /// failures in, and a banner about the last connect says nothing about
  /// whether there is a core to ask.
  bool get _isTunnelUp => switch (ref.read(coreStatusProvider).value) {
        TunnelConnected() || TunnelChecking() => true,
        _ => false,
      };

  Future<CommyFailure?> _measure(
    ProxyNode node, {
    required bool throughCore,
  }) async {
    final result = await ref.read(measureLatencyUseCaseProvider)(
      node: node,
      outboundTag: SingBoxTags.forNode(node),
      throughCore: throughCore,
    );
    return result.failureOrNull;
  }
}
