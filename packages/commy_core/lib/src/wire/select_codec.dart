import 'dart:convert';

import 'package:commy_core/src/wire/wire_json.dart';
import 'package:commy_core/src/wire/wire_keys.dart';
import 'package:commy_domain/commy_domain.dart';

/// Builds the `select` argument and reads it back.
///
/// `select` is how the active node changes while the tunnel stays up. The
/// alternative — reload with a new configuration — tears down every open
/// connection, which the user experiences as a dropped call and a download that
/// died halfway (`docs/wire-protocol.md`, "select").
abstract final class SelectCodec {
  /// Builds the JSON argument: `{"group": "proxy", "tag": "node-7f3c1a"}`.
  static String encodeRequest({required String group, required String tag}) =>
      jsonEncode(encode(group: group, tag: tag));

  /// Builds the argument as an object, for tests and for the fake.
  static JsonMap encode({required String group, required String tag}) =>
      <String, Object?>{WireKeys.group: group, WireKeys.tag: tag};

  /// Reads the argument back. The native side does the same in Kotlin.
  static ({String group, String tag}) decode(Object? raw) {
    final json = WireJson.object(raw, 'select argument');
    return (
      group: WireJson.stringOr(
        json,
        WireKeys.group,
        orElse: SwitchNodeUseCase.defaultGroupTag,
      ),
      tag: WireJson.stringOr(json, WireKeys.tag, orElse: ''),
    );
  }
}
