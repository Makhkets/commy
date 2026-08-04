import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/redaction.dart';

/// One entry that could not be imported, and why.
///
/// Partial success is success: forty nodes out of fifty are imported and the
/// remaining ten land here with a reason the user can act on
/// (docs/06-data-model.md, "Правила парсера").
///
/// [rawLine] is the original input, so it usually holds a UUID or a password.
/// Use [redacted] before it reaches a log or an export (rule R3).
class ImportFailure {
  /// Creates an import failure.
  const ImportFailure({required this.rawLine, required this.reason});

  /// Restores an import failure from the map produced by [toJson].
  factory ImportFailure.fromJson(JsonMap json) => ImportFailure(
        rawLine: JsonRead.string(json, 'rawLine'),
        reason: JsonRead.string(json, 'reason'),
      );

  /// The input we could not parse, verbatim. Contains credentials.
  final String rawLine;

  /// Why it failed, in words the user can act on.
  final String reason;

  /// The input with credentials removed, safe to show and to export.
  String get redactedLine => Redact.link(rawLine);

  /// A copy safe to print.
  ImportFailure redacted() =>
      ImportFailure(rawLine: redactedLine, reason: reason);

  /// Returns a copy with the given fields replaced.
  ImportFailure copyWith({String? rawLine, String? reason}) => ImportFailure(
        rawLine: rawLine ?? this.rawLine,
        reason: reason ?? this.reason,
      );

  /// Serialises the failure, raw line included.
  JsonMap toJson() => <String, Object?>{
        'rawLine': rawLine,
        'reason': reason,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportFailure &&
          other.rawLine == rawLine &&
          other.reason == reason;

  @override
  int get hashCode => Object.hash(rawLine, reason);

  /// Never prints [rawLine] unredacted.
  @override
  String toString() => 'ImportFailure($redactedLine, $reason)';
}
