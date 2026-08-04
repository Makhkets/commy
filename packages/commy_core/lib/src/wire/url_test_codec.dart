import 'dart:convert';

import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `urlTest` argument and reads its answer.
///
/// The method looks asymmetric on purpose. libbox's `CommandClient.urlTest`
/// measures a *whole group* and delivers the numbers asynchronously through
/// `writeGroups`, while the domain port asks for the latency of one outbound
/// and expects it back from the call. The wait is therefore hidden on the
/// Kotlin side, and this codec only sees the tidy shape
/// (`docs/wire-protocol.md`, "urlTest").
abstract final class UrlTestCodec {
  /// How long the native side waits for the group refresh, by default.
  static const Duration defaultTimeout = Duration(seconds: 5);

  /// Group measured when the caller did not name one.
  static const String defaultGroup = SwitchNodeUseCase.defaultGroupTag;

  /// Builds the JSON argument for `urlTest`.
  static String encodeRequest({
    required String tag,
    required Uri probe,
    String group = defaultGroup,
    Duration timeout = defaultTimeout,
  }) =>
      jsonEncode(<String, Object?>{
        WireKeys.tag: tag,
        WireKeys.url: probe.toString(),
        WireKeys.timeoutMs: timeout.inMilliseconds,
        WireKeys.group: group,
      });

  /// Reads the `urlTest` answer.
  ///
  /// `null` is the honest result for "the probe did not come back", not an
  /// error: `MeasureLatencyUseCase` turns it into `Ok(null)` and the list draws
  /// a dash. Throwing here would make an unreachable node indistinguishable
  /// from a broken app.
  ///
  /// A delay of zero means *not measured* rather than *instant*, and collapses
  /// to `null` for the same reason — a node nobody probed must never sort above
  /// one that answered in 12 ms.
  static Duration? decodeDelay(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is num) {
      return _duration(raw.toInt());
    }
    final json = WireJson.object(raw, 'urlTest result');
    return _duration(WireJson.integerOrNull(json, WireKeys.delayMs));
  }

  /// Builds the JSON answer. Used by the fake and by the contract tests.
  static JsonMap encodeResponse(Duration? delay) => <String, Object?>{
        WireKeys.delayMs: delay?.inMilliseconds,
      };

  static Duration? _duration(int? millis) =>
      millis == null || millis <= 0 ? null : Duration(milliseconds: millis);
}
