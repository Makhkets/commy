import 'dart:convert';

import 'package:commy_domain/commy_domain.dart';

/// JSON encoded into a single text column, and back.
///
/// Several tables keep a small object in one column — protocol parameters,
/// the quota block, the settings blob. They all go through here so the encoding
/// is identical everywhere and a corrupted value degrades to an empty map
/// instead of throwing inside a stream.
abstract final class JsonText {
  /// What an absent or unreadable object decodes to.
  static const JsonMap emptyObject = <String, Object?>{};

  /// Encodes [value] for storage. An empty map still encodes to `{}`.
  static String encode(JsonMap value) => jsonEncode(value);

  /// Decodes [raw], throwing when it is not a JSON object.
  ///
  /// Strict on purpose: the caller is inside `StorageGuard` and turns the
  /// throw into a `StorageFailure`, which is louder than a silently empty row.
  static JsonMap decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('expected a JSON object', raw);
    }
    return decoded;
  }

  /// Decodes [raw], falling back to [emptyObject] on anything unexpected.
  ///
  /// For the stream side, where one bad row must not kill the subscription.
  static JsonMap decodeOrEmpty(String? raw) {
    if (raw == null || raw.isEmpty) {
      return emptyObject;
    }
    try {
      return decode(raw);
    } on Object catch (_) {
      return emptyObject;
    }
  }
}
