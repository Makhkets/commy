/// One day of traffic, as two totals.
///
/// Two numbers a day and nothing else. There is no per-connection record and
/// there will not be one — that would be a browsing history, which is the
/// artefact this project exists not to keep (docs/09-security-privacy.md).
class TrafficDay {
  /// Creates a day.
  const TrafficDay({
    required this.day,
    required this.scope,
    required this.upBytes,
    required this.downBytes,
  });

  /// The scope of the unattributed total: every server together.
  static const String allScope = '';

  /// Local midnight of the day the bytes belong to.
  final DateTime day;

  /// A node id, or [allScope].
  final String scope;

  /// Bytes sent.
  final int upBytes;

  /// Bytes received.
  final int downBytes;

  /// Sent and received together.
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
