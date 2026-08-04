import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Reads and writes `/logs` events.
///
/// The channel carries either one object or a whole batch, because
/// `CommandClientHandler.writeLogs` hands over a `LogIterator` and splitting it
/// into one event per line buys nothing (`docs/wire-protocol.md`, "/logs").
///
/// Messages arrive raw and stay raw here. Redaction is `AppLogger`'s job, one
/// layer up: the native side has no idea which substrings are credentials, and
/// guessing with a regex over there would cut the useful half and leave the
/// dangerous half (rule R3).
abstract final class LogLineCodec {
  /// Matches a severity the core left inside the text.
  ///
  /// Covers the three shapes sing-box and its dependencies actually produce:
  /// `INFO[0001] …`, `[warn] …` and `level=error …`.
  static final RegExp levelPattern = RegExp(
    r'^\s*\[?(trace|debug|info|warn|warning|error|fatal|panic)\b\]?'
    r'|\blevel\s*[=:]\s*"?(trace|debug|info|warn|warning|error|fatal|panic)\b',
    caseSensitive: false,
  );

  /// Decodes one or many `/logs` events.
  ///
  /// [fallbackAt] stands in for a missing timestamp.
  static List<LogLine> decodeList(Object? raw, {DateTime? fallbackAt}) {
    final at = fallbackAt ?? DateTime.now();
    return <LogLine>[
      for (final json in WireJson.objectList(raw, '/logs event'))
        _decodeObject(json, at),
    ];
  }

  /// Decodes a single `/logs` object.
  static LogLine decode(Object? raw, {DateTime? fallbackAt}) => _decodeObject(
        WireJson.object(raw, '/logs event'),
        fallbackAt ?? DateTime.now(),
      );

  /// Encodes [line] back into the wire shape.
  static JsonMap encode(LogLine line) => <String, Object?>{
        WireKeys.level: line.level.wireName,
        WireKeys.message: line.message,
        WireKeys.at: line.at.toUtc().millisecondsSinceEpoch,
        WireKeys.tag: line.tag,
      };

  /// Pulls a severity out of a line the core did not label.
  ///
  /// Returns `null` when the text carries no recognisable level. The matched
  /// prefix is *not* removed: the rest of that token is often an uptime counter
  /// (`INFO[0001]`), and a log that no longer matches what the core printed is
  /// harder to cross-reference, which is the whole point of exporting one.
  static LogLevel? sniffLevel(String message) {
    final match = levelPattern.firstMatch(message);
    if (match == null) {
      return null;
    }
    final name = match.group(1) ?? match.group(2);
    return name == null ? null : LogLevel.fromWireName(name);
  }

  static LogLine _decodeObject(JsonMap json, DateTime fallbackAt) {
    final message = WireJson.stringOr(json, WireKeys.message, orElse: '');
    final declared = WireJson.stringOrNull(json, WireKeys.level);
    final level = (declared == null ? null : LogLevel.fromWireName(declared)) ??
        sniffLevel(message) ??
        LogLevel.info;
    return LogLine(
      level: level,
      message: message,
      at: WireJson.epochMillisOr(json, WireKeys.at, orElse: fallbackAt),
      tag: WireJson.stringOrNull(json, WireKeys.tag),
    );
  }
}
