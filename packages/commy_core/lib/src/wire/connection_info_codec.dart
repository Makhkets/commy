import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `/connections` snapshots.
///
/// The channel carries the whole list every time, never a delta. libbox's own
/// `ConnectionEvents` is incremental, and folding that into a snapshot is the
/// native side's job: Dart cannot tell "this connection closed" apart from
/// "that event went missing" (`docs/wire-protocol.md`, "/connections").
///
/// Only `id` is required. Everything else falls back, because a row with a
/// blank field still answers the question the screen exists for — why is this
/// host going out through that outbound — while a dropped snapshot answers
/// nothing.
abstract final class ConnectionInfoCodec {
  /// Transport assumed when the core did not say.
  static const String defaultNetwork = 'tcp';

  /// Decodes one `/connections` snapshot.
  ///
  /// [fallbackStart] stands in for a missing `start`. Entries without an `id`
  /// are skipped: without one the UI cannot keep a row stable across snapshots,
  /// which is exactly what makes the list readable while it churns.
  static List<ConnectionInfo> decodeList(
    Object? raw, {
    DateTime? fallbackStart,
  }) {
    final start = fallbackStart ?? DateTime.now();
    final result = <ConnectionInfo>[];
    for (final json in WireJson.objectList(raw, '/connections event')) {
      final id = WireJson.stringOrNull(json, WireKeys.id);
      if (id == null) {
        continue;
      }
      result.add(_decodeObject(json, id, start));
    }
    return result;
  }

  /// Encodes [connection] back into the wire shape.
  static JsonMap encode(ConnectionInfo connection) => <String, Object?>{
        WireKeys.id: connection.id,
        WireKeys.host: connection.host,
        WireKeys.rule: connection.rule,
        WireKeys.outbound: connection.outbound,
        WireKeys.up: connection.uploadTotal,
        WireKeys.down: connection.downloadTotal,
        WireKeys.start: connection.start.toUtc().millisecondsSinceEpoch,
        WireKeys.network: connection.network,
      };

  static ConnectionInfo _decodeObject(
    JsonMap json,
    String id,
    DateTime fallbackStart,
  ) {
    return ConnectionInfo(
      id: id,
      host: WireJson.stringOr(json, WireKeys.host, orElse: ''),
      rule: WireJson.stringOr(json, WireKeys.rule, orElse: ''),
      outbound: WireJson.stringOr(json, WireKeys.outbound, orElse: ''),
      uploadTotal: WireJson.integerOr(json, WireKeys.up, orElse: 0),
      downloadTotal: WireJson.integerOr(json, WireKeys.down, orElse: 0),
      start: WireJson.epochMillisOr(
        json,
        WireKeys.start,
        orElse: fallbackStart,
      ),
      network: WireJson.stringOr(
        json,
        WireKeys.network,
        orElse: defaultNetwork,
      ),
    );
  }
}
