import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
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
/// How a server is timed is the "Ping" setting's call — a GET through it by
/// default, or a TCP handshake, or an echo; see `MeasureLatencyUseCase`. It is
/// read once per run, so the numbers inside one run are always comparable,
/// and it no longer matters whether the tunnel is up.
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
    this.skipped = 0,
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

  /// How many servers the last run left alone because the chosen method
  /// cannot time them — servers on UDP, with the TCP method.
  ///
  /// Reported rather than dropped: a run that silently skips three rows looks
  /// exactly like a run that broke on them.
  final int skipped;

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
          other.skipped == skipped;

  @override
  int get hashCode => Object.hash(scopeId, done, total, failure, skipped);

  @override
  String toString() => 'MeasurementState($scopeId, $done/$total, $failure)';
}

/// Runs a batch of latency probes and reports on it.
class MeasurementController extends Notifier<MeasurementState> {
  /// How many probes are in flight at once.
  ///
  /// Not one, and not thirty. Sequential made a subscription of thirty
  /// servers take half a minute; all at once times the phone's own link more
  /// than the servers. A new probe starts as soon as one finishes, so a
  /// server that never answers holds one slot for its timeout, not a batch.
  static const int inFlight = 6;

  @override
  MeasurementState build() => MeasurementState.idle;

  /// The run that is currently allowed to continue.
  ///
  /// Bumped by [cancel] and by every new run, so a probe that finishes after
  /// its run was called off writes no progress and starts nothing further.
  int _generation = 0;

  /// Probes one server, for the "measure" row of its menu.
  ///
  /// No progress to show — the number landing on the row is the report — but
  /// the same rules as a run: a failure is this controller's to announce, and
  /// a server the method cannot time says so instead of failing.
  Future<void> measureOne(ProxyNode node) async {
    if (!MeasureLatencyUseCase.canMeasure(node, _method)) {
      state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
        skipped: 1,
      );
      return;
    }
    final failure = await _measure(node);
    if (failure != null) {
      state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
        failure: failure,
      );
    }
  }

  /// Probes every node in [nodes], [inFlight] at a time.
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
    // Read once, so every number in the run was taken the same way.
    final method = _method;
    final measurable = <ProxyNode>[
      for (final node in nodes)
        if (MeasureLatencyUseCase.canMeasure(node, method)) node,
    ];
    final skipped = nodes.length - measurable.length;
    if (measurable.isEmpty) {
      state = MeasurementState(skipped: skipped);
      return;
    }

    final generation = ++_generation;
    state = MeasurementState(scopeId: scopeId, total: measurable.length);

    var next = 0;
    var done = 0;
    Future<void> worker() async {
      while (generation == _generation && next < measurable.length) {
        final node = measurable[next++];
        final failure = await _measure(node);
        if (generation != _generation) {
          return;
        }
        done++;
        state = MeasurementState(
          scopeId: scopeId,
          done: done,
          total: measurable.length,
          // The last thing that went wrong, not the first: the freshest
          // failure is the one worth putting in front of the user.
          failure: failure ?? state.failure,
        );
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < inFlight && i < measurable.length; i++) worker(),
    ]);
    if (generation != _generation) {
      return;
    }
    state = MeasurementState(failure: state.failure, skipped: skipped);
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

  /// Drops the last failure, and the "skipped" count, once shown.
  void clearFailure() => state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
      );

  /// The "Ping" setting, as the settings screen last saved it.
  PingMethod get _method =>
      (ref.read(settingsProvider).value ?? AppSettings.defaults).pingMethod;

  Future<CommyFailure?> _measure(ProxyNode node) async {
    final result = await ref.read(measureLatencyUseCaseProvider)(
      node: node,
      outboundTag: SingBoxTags.forNode(node),
    );
    return result.failureOrNull;
  }
}
