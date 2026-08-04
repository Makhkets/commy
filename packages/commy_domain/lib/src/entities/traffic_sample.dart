/// One tick of throughput reported by the core.
///
/// [uplink] and [downlink] are instantaneous rates in bytes per second;
/// [uplinkTotal] and [downlinkTotal] are cumulative byte counters since the
/// tunnel came up.
class TrafficSample {
  /// Creates a sample.
  const TrafficSample({
    required this.uplink,
    required this.downlink,
    required this.uplinkTotal,
    required this.downlinkTotal,
    required this.at,
  });

  /// Bytes per second going out.
  final int uplink;

  /// Bytes per second coming in.
  final int downlink;

  /// Bytes sent since the tunnel came up.
  final int uplinkTotal;

  /// Bytes received since the tunnel came up.
  final int downlinkTotal;

  /// When the sample was taken.
  final DateTime at;

  /// Combined instantaneous rate, in bytes per second.
  int get rate => uplink + downlink;

  /// Combined cumulative volume, in bytes.
  int get totalBytes => uplinkTotal + downlinkTotal;

  /// Returns a copy with the given fields replaced.
  TrafficSample copyWith({
    int? uplink,
    int? downlink,
    int? uplinkTotal,
    int? downlinkTotal,
    DateTime? at,
  }) {
    return TrafficSample(
      uplink: uplink ?? this.uplink,
      downlink: downlink ?? this.downlink,
      uplinkTotal: uplinkTotal ?? this.uplinkTotal,
      downlinkTotal: downlinkTotal ?? this.downlinkTotal,
      at: at ?? this.at,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficSample &&
          other.uplink == uplink &&
          other.downlink == downlink &&
          other.uplinkTotal == uplinkTotal &&
          other.downlinkTotal == downlinkTotal &&
          other.at == at;

  @override
  int get hashCode =>
      Object.hash(uplink, downlink, uplinkTotal, downlinkTotal, at);

  @override
  String toString() =>
      'TrafficSample(up: $uplink/s, down: $downlink/s, at: $at)';
}
