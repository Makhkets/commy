import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_domain/commy_domain.dart';

/// Turns Clash API payloads into domain entities.
///
/// The Clash API is sing-box's own HTTP surface, so the shapes here are *not*
/// the shapes in `docs/wire-protocol.md` — that protocol is ours and describes
/// the Android channels. This one is somebody else's and describes desktop.
/// Keeping the two apart in separate files is deliberate: they drift
/// independently, and a shared "generic" decoder would end up lenient enough to
/// accept neither properly.
///
/// Everything is read defensively. The core on the other end may be a version
/// ahead, and a diagnostics screen that throws on an unfamiliar field is worse
/// than one that shows a blank column.
abstract final class ClashCodec {
  /// Wrapper key of the `GET /proxies` answer.
  static const String proxiesKey = 'proxies';

  /// Wrapper key of the `GET /connections` answer.
  static const String connectionsKey = 'connections';

  /// Transport assumed when the metadata does not say.
  static const String defaultNetwork = 'tcp';

  /// Decodes `GET /proxies`.
  ///
  /// Only entries that carry an `all` list come back: those are the groups. A
  /// plain outbound has no members and would turn into a group of one, which is
  /// not something the node screen has any use for.
  static List<ProxyGroup> decodeProxies(Object? raw) {
    final root = WireJson.object(raw, 'GET /proxies');
    final table = WireJson.asMap(root[proxiesKey]);
    if (table == null) {
      return const <ProxyGroup>[];
    }
    final groups = <ProxyGroup>[];
    for (final entry in table.entries) {
      final node = WireJson.asMap(entry.value);
      if (node == null || node['all'] is! List<Object?>) {
        continue;
      }
      groups.add(
        ProxyGroup(
          tag: entry.key,
          type: WireJson.stringOr(node, 'type', orElse: 'selector'),
          now: WireJson.stringOrNull(node, 'now'),
          all: WireJson.stringList(node, 'all'),
        ),
      );
    }
    return groups;
  }

  /// Decodes `GET /proxies/{tag}/delay`.
  ///
  /// A zero or missing delay is `null` — "did not answer" — for the same reason
  /// it is on the mobile path: an unmeasured node must never sort above one
  /// that actually replied.
  static Duration? decodeDelay(Object? raw) {
    final json = WireJson.object(raw, 'GET /proxies/{tag}/delay');
    final millis = WireJson.integerOrNull(json, 'delay');
    return millis == null || millis <= 0
        ? null
        : Duration(milliseconds: millis);
  }

  /// Decodes one line of `GET /traffic`.
  ///
  /// Clash reports rates only; the cumulative counters live on
  /// `GET /connections`. [uplinkTotal] and [downlinkTotal] carry the last ones
  /// seen there, which is how a Clash client assembles a whole
  /// [TrafficSample].
  static TrafficSample decodeTraffic(
    Object? raw, {
    required int uplinkTotal,
    required int downlinkTotal,
    DateTime? at,
  }) {
    final json = WireJson.object(raw, 'GET /traffic');
    return TrafficSample(
      uplink: WireJson.integerOr(json, 'up', orElse: 0),
      downlink: WireJson.integerOr(json, 'down', orElse: 0),
      uplinkTotal: uplinkTotal,
      downlinkTotal: downlinkTotal,
      at: at ?? DateTime.now(),
    );
  }

  /// Decodes one line of `GET /logs`.
  ///
  /// Clash spells the fields `type` and `payload`; our own protocol spells them
  /// `level` and `message`. Both are accepted, because the same decoder is the
  /// obvious thing to reach for while debugging one against the other.
  static LogLine decodeLog(Object? raw, {DateTime? at}) {
    final json = WireJson.object(raw, 'GET /logs');
    final message = WireJson.stringOrNull(json, 'payload') ??
        WireJson.stringOr(json, 'message', orElse: '');
    final name = WireJson.stringOrNull(json, 'type') ??
        WireJson.stringOrNull(json, 'level');
    return LogLine(
      level: (name == null ? null : LogLevel.fromWireName(name)) ??
          LogLevel.info,
      message: message,
      at: at ?? DateTime.now(),
    );
  }

  /// Decodes `GET /connections`.
  ///
  /// Returns the snapshot together with the cumulative byte counters, which is
  /// the only place the Clash API exposes them.
  static ({
    List<ConnectionInfo> connections,
    int uplinkTotal,
    int downlinkTotal,
  }) decodeConnections(Object? raw, {DateTime? fallbackStart}) {
    final root = WireJson.object(raw, 'GET /connections');
    final start = fallbackStart ?? DateTime.now();
    final rows = root[connectionsKey];
    final connections = <ConnectionInfo>[];
    if (rows is List<Object?>) {
      for (final row in rows) {
        final json = WireJson.asMap(row);
        final id = json == null ? null : WireJson.stringOrNull(json, 'id');
        if (json == null || id == null) {
          continue;
        }
        connections.add(_connection(json, id, start));
      }
    }
    return (
      connections: connections,
      uplinkTotal: WireJson.integerOr(root, 'uploadTotal', orElse: 0),
      downlinkTotal: WireJson.integerOr(root, 'downloadTotal', orElse: 0),
    );
  }

  static ConnectionInfo _connection(
    JsonMap json,
    String id,
    DateTime fallbackStart,
  ) {
    final metadata =
        WireJson.asMap(json['metadata']) ?? const <String, Object?>{};
    final chains = WireJson.stringList(json, 'chains');
    return ConnectionInfo(
      id: id,
      host: _host(metadata),
      rule: _rule(json),
      outbound: chains.isEmpty ? '' : chains.first,
      uploadTotal: WireJson.integerOr(json, 'upload', orElse: 0),
      downloadTotal: WireJson.integerOr(json, 'download', orElse: 0),
      start: _start(json['start']) ?? fallbackStart,
      network: WireJson.stringOr(
        metadata,
        'network',
        orElse: defaultNetwork,
      ),
    );
  }

  static String _host(JsonMap metadata) {
    final host = WireJson.stringOrNull(metadata, 'host') ??
        WireJson.stringOrNull(metadata, 'destinationIP') ??
        '';
    final port = WireJson.stringOrNull(metadata, 'destinationPort');
    if (host.isEmpty || port == null) {
      return host;
    }
    return '$host:$port';
  }

  static String _rule(JsonMap json) {
    final rule = WireJson.stringOr(json, 'rule', orElse: '');
    final payload = WireJson.stringOrNull(json, 'rulePayload');
    if (rule.isEmpty || payload == null) {
      return rule;
    }
    return '$rule($payload)';
  }

  /// Reads `start`, which Clash writes as RFC 3339 and libbox as epoch millis.
  static DateTime? _start(Object? raw) {
    if (raw is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        raw.toInt(),
        isUtc: true,
      ).toLocal();
    }
    if (raw is String) {
      return DateTime.tryParse(raw)?.toLocal();
    }
    return null;
  }
}
