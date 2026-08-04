import 'package:flutter/foundation.dart' show immutable;

/// Traffic totals for one calendar day.
///
/// A data-layer type, not a domain entity: the domain models the live tick
/// (`TrafficSample`), while this is the aggregate the statistics screen draws.
/// The distinction is the point — raw connections are never persisted, only
/// two numbers per day (docs/06-data-model.md).
@immutable
class TrafficDay {
  /// Creates a day total.
  const TrafficDay({
    required this.day,
    required this.scope,
    required this.upBytes,
    required this.downBytes,
  });

  /// Value of [scope] meaning "everything, not attributed to a node".
  static const String allScope = '';

  /// Local calendar day, at midnight.
  final DateTime day;

  /// Node id the row counts, or [allScope].
  final String scope;

  /// Bytes sent that day.
  final int upBytes;

  /// Bytes received that day.
  final int downBytes;

  /// Bytes moved in either direction.
  int get totalBytes => upBytes + downBytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficDay &&
          other.day == day &&
          other.scope == scope &&
          other.upBytes == upBytes &&
          other.downBytes == downBytes;

  @override
  int get hashCode => Object.hash(day, scope, upBytes, downBytes);

  @override
  String toString() =>
      'TrafficDay($day, $scope, up: $upBytes, down: $downBytes)';
}
