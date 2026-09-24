import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart';

/// What a finished measurement found, in the few numbers a toast can hold.
///
/// Published once, at the end of a run that was not cancelled, so the
/// announcement is decided by the numbers the run actually produced rather
/// than by re-reading rows that another refresh may already have replaced.
@immutable
class MeasurementReport {
  /// Creates a report.
  const MeasurementReport({
    required this.measured,
    required this.reachable,
    this.node,
    this.latency,
    this.skipped = 0,
  });

  /// Sums up [results] — each server that was probed, with its round trip or
  /// `null` when it did not answer — plus the [skipped] ones nobody probed.
  ///
  /// The quickest answer wins; a tie goes to the server listed first, so the
  /// same numbers always name the same server.
  factory MeasurementReport.of(
    List<(ProxyNode, Duration?)> results, {
    int skipped = 0,
  }) {
    ProxyNode? fastest;
    Duration? best;
    var reachable = 0;
    for (final (node, latency) in results) {
      if (latency == null) {
        continue;
      }
      reachable++;
      if (best == null || latency < best) {
        best = latency;
        fastest = node;
      }
    }
    final single = results.length == 1 ? results.single : null;
    return MeasurementReport(
      measured: results.length,
      reachable: reachable,
      node: single?.$1 ?? fastest,
      latency: single?.$2 ?? best,
      skipped: skipped,
    );
  }

  /// How many servers were probed.
  ///
  /// A server whose probe could not even be built — a transport the core
  /// does not carry — is one of them, and counts as one that did not answer:
  /// the run's failure is only said instead of this report when nothing
  /// answered at all (see `NoticeHost`).
  final int measured;

  /// How many of them answered.
  final int reachable;

  /// The server the report names: the quickest one that answered — or, when
  /// only one was measured, that one, whether it answered or not.
  final ProxyNode? node;

  /// [node]'s round trip; `null` when it did not answer.
  final Duration? latency;

  /// How many servers the method could not time and so left alone.
  final int skipped;

  /// Whether the report is about a single server, which is said by its name
  /// rather than as "1 of 1".
  bool get isSingle => measured == 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeasurementReport &&
          other.measured == measured &&
          other.reachable == reachable &&
          other.node == node &&
          other.latency == latency &&
          other.skipped == skipped;

  @override
  int get hashCode => Object.hash(measured, reachable, node, latency, skipped);

  @override
  String toString() => 'MeasurementReport($reachable/$measured, '
      '${node?.id} ${latency?.inMilliseconds} ms, skipped $skipped)';
}
