/// One live connection the core is carrying, as shown on the diagnostics
/// screen.
///
/// Connections are never persisted — only the daily traffic aggregate is
/// (docs/06-data-model.md).
class ConnectionInfo {
  /// Creates a connection record.
  const ConnectionInfo({
    required this.id,
    required this.host,
    required this.rule,
    required this.outbound,
    required this.uploadTotal,
    required this.downloadTotal,
    required this.start,
    required this.network,
  });

  /// Identifier assigned by the core.
  final String id;

  /// Destination host, sniffed or resolved.
  final String host;

  /// Routing rule that matched, in the core's own wording.
  final String rule;

  /// Tag of the outbound the traffic was handed to.
  final String outbound;

  /// Bytes sent on this connection.
  final int uploadTotal;

  /// Bytes received on this connection.
  final int downloadTotal;

  /// When the connection opened.
  final DateTime start;

  /// Transport, as the core reports it: `tcp` or `udp`.
  final String network;

  /// Combined volume, in bytes.
  int get totalBytes => uploadTotal + downloadTotal;

  /// How long the connection has been open at [now].
  Duration ageAt(DateTime now) => now.difference(start);

  /// Returns a copy with the given fields replaced.
  ConnectionInfo copyWith({
    String? id,
    String? host,
    String? rule,
    String? outbound,
    int? uploadTotal,
    int? downloadTotal,
    DateTime? start,
    String? network,
  }) {
    return ConnectionInfo(
      id: id ?? this.id,
      host: host ?? this.host,
      rule: rule ?? this.rule,
      outbound: outbound ?? this.outbound,
      uploadTotal: uploadTotal ?? this.uploadTotal,
      downloadTotal: downloadTotal ?? this.downloadTotal,
      start: start ?? this.start,
      network: network ?? this.network,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionInfo &&
          other.id == id &&
          other.host == host &&
          other.rule == rule &&
          other.outbound == outbound &&
          other.uploadTotal == uploadTotal &&
          other.downloadTotal == downloadTotal &&
          other.start == start &&
          other.network == network;

  @override
  int get hashCode => Object.hash(
        id,
        host,
        rule,
        outbound,
        uploadTotal,
        downloadTotal,
        start,
        network,
      );

  @override
  String toString() => 'ConnectionInfo($id, $network, $host, $outbound)';
}
