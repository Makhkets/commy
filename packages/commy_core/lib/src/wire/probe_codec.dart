import 'dart:convert';

import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the arguments of `probeOutbounds` and `ping` and reads their
/// answers — the "Ping" setting's GET and ICMP (`docs/wire-protocol.md`).
abstract final class ProbeCodec {
  /// The argument of `probeOutbounds`.
  ///
  /// The configuration travels as a string inside the JSON, not as an object:
  /// Kotlin hands it to the core as it is, and a round trip through
  /// `JSONObject` would be a parse and a print for nothing.
  static String encodeOutbounds(
    CoreConfig config, {
    required Uri probe,
    required Duration timeout,
  }) =>
      jsonEncode(<String, Object?>{
        WireKeys.config: config.encode(),
        WireKeys.url: probe.toString(),
        WireKeys.timeoutMs: timeout.inMilliseconds,
      });

  /// Reads the answer of `probeOutbounds`: `{tag: milliseconds}`.
  ///
  /// Zero is "did not answer" and becomes `null`, as a delay of zero does
  /// everywhere on this wire: a server nobody heard from must never sort
  /// above one that answered in 12 ms.
  static Map<String, Duration?> decodeOutbounds(Object? raw) {
    final json = WireJson.object(raw, 'probeOutbounds result');
    return <String, Duration?>{
      for (final entry in json.entries)
        entry.key: switch (entry.value) {
          final num millis when millis > 0 =>
            Duration(milliseconds: millis.toInt()),
          _ => null,
        },
    };
  }

  /// The argument of `ping`.
  static String encodePing(String host, {required Duration timeout}) =>
      jsonEncode(<String, Object?>{
        WireKeys.host: host,
        WireKeys.timeoutMs: timeout.inMilliseconds,
      });
}
