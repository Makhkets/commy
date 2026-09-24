import 'package:commy/src/di/use_case_providers.dart';
import 'package:commy/src/state/library_providers.dart';
import 'package:commy/src/state/measurement_report.dart';
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
    this.report,
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
  ///
  /// Published next to [report] at the end of a run; which of the two is
  /// said is `NoticeHost`'s call — the failure only when nothing answered.
  final CommyFailure? failure;

  /// How many servers the last run left alone because the chosen method
  /// cannot time them — servers on UDP, with the TCP method.
  ///
  /// Reported rather than dropped: a run that silently skips three rows looks
  /// exactly like a run that broke on them.
  final int skipped;

  /// What the last finished measurement found — a whole run that was not
  /// cancelled, or one server from its menu.
  ///
  /// The measurement is the user's own request, and the numbers landing on
  /// the rows were its only answer: a run of seventeen servers ended with the
  /// progress row simply disappearing, and a single probe changed one figure
  /// somewhere down the list. The owner asked for the result to be said.
  final MeasurementReport? report;

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
          other.skipped == skipped &&
          other.report == report;

  @override
  int get hashCode =>
      Object.hash(scopeId, done, total, failure, skipped, report);

  @override
  String toString() =>
      'MeasurementState($scopeId, $done/$total, $failure, $report)';
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

  /// The last thing that went wrong in the current run.
  ///
  /// Kept here rather than in the progress state: a failure written into
  /// every step was announced in the middle of the run, then again by
  /// whatever came next, and the end of the run had no single thing to say.
  CommyFailure? _runFailure;

  /// Probes one server, for the "measure" row of its menu.
  ///
  /// No progress to show, but the same rules as a run: the result is said
  /// out loud, a failure is this controller's to announce, and a server the
  /// method cannot time says so instead of failing.
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
    final (latency, failure) = await _measure(node);
    state = MeasurementState(
      scopeId: state.scopeId,
      done: state.done,
      total: state.total,
      failure: failure,
      report: failure == null
          ? MeasurementReport.of(<(ProxyNode, Duration?)>[(node, latency)])
          : null,
    );
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
    _runFailure = null;
    state = MeasurementState(scopeId: scopeId, total: measurable.length);

    // By position, so the report names the first of two equally quick
    // servers in the order the list shows them, not in the order they
    // happened to come back.
    final results = List<(ProxyNode, Duration?)?>.filled(
      measurable.length,
      null,
    );
    var next = 0;
    var done = 0;
    Future<void> worker() async {
      while (generation == _generation && next < measurable.length) {
        final index = next++;
        final node = measurable[index];
        final (latency, failure) = await _measure(node);
        if (generation != _generation) {
          return;
        }
        results[index] = (node, latency);
        // The last thing that went wrong, not the first: the freshest
        // failure is the one worth putting in front of the user.
        _runFailure = failure ?? _runFailure;
        done++;
        state = MeasurementState(
          scopeId: scopeId,
          done: done,
          total: measurable.length,
        );
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < inFlight && i < measurable.length; i++) worker(),
    ]);
    if (generation != _generation) {
      return;
    }
    state = MeasurementState(
      failure: _runFailure,
      skipped: skipped,
      report: MeasurementReport.of(
        <(ProxyNode, Duration?)>[
          for (final result in results)
            if (result != null) result,
        ],
        skipped: skipped,
      ),
    );
  }

  /// Stops the run. Probes already in flight finish and their numbers are
  /// kept — a measurement that came back is still true.
  ///
  /// A stopped run reports nothing: the user called it off, and "3 of 17
  /// answer" about a run they abandoned would be a number about nothing.
  /// A failure it already hit is still said — that is not about the run.
  void cancel() {
    if (!state.isRunning) {
      return;
    }
    _generation++;
    state = MeasurementState(failure: _runFailure);
  }

  /// Drops the last failure, report and "skipped" count, once shown.
  void clearOutcome() => state = MeasurementState(
        scopeId: state.scopeId,
        done: state.done,
        total: state.total,
      );

  /// The "Ping" setting, as the settings screen last saved it.
  PingMethod get _method =>
      (ref.read(settingsProvider).value ?? AppSettings.defaults).pingMethod;

  /// The round trip — `null` when the server did not answer — or what
  /// stopped it from being taken.
  Future<(Duration?, CommyFailure?)> _measure(ProxyNode node) async {
    final result = await ref.read(measureLatencyUseCaseProvider)(
      node: node,
      outboundTag: SingBoxTags.forNode(node),
    );
    return (result.valueOrNull, result.failureOrNull);
  }
}
