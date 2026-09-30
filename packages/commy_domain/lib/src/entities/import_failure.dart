import 'package:commy_domain/src/core/json_map.dart';
import 'package:commy_domain/src/core/json_read.dart';
import 'package:commy_domain/src/core/redaction.dart';
import 'package:commy_domain/src/entities/import_failure_kind.dart';

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
  const ImportFailure({
    required this.rawLine,
    required this.reason,
    this.kind = ImportFailureKind.malformed,
    this.subject,
  });

  /// Restores an import failure from the map produced by [toJson].
  ///
  /// A map from before [kind] existed, or naming a kind this build does not
  /// know, reads as [ImportFailureKind.malformed].
  factory ImportFailure.fromJson(JsonMap json) => ImportFailure(
        rawLine: JsonRead.string(json, 'rawLine'),
        reason: JsonRead.string(json, 'reason'),
        kind: ImportFailureKind.values.asNameMap()[json['kind']] ??
            ImportFailureKind.malformed,
        subject: JsonRead.stringOrNull(json, 'subject'),
      );

  /// The input we could not parse, verbatim. Contains credentials.
  final String rawLine;

  /// Why it failed, in English, for the log. What the user reads is worded
  /// from [kind] and [subject].
  final String reason;

  /// Why it failed, as the app words it.
  final ImportFailureKind kind;

  /// What [kind] is about in particular — a scheme, a transport, a type —
  /// or `null`. Never a credential: it names a feature, not a value.
  final String? subject;

  /// The input with credentials removed, safe to show and to export.
  String get redactedLine => Redact.link(rawLine);

  /// A copy safe to print.
  ImportFailure redacted() => copyWith(rawLine: redactedLine);

  /// Returns a copy with the given fields replaced.
  ImportFailure copyWith({
    String? rawLine,
    String? reason,
    ImportFailureKind? kind,
    String? subject,
  }) =>
      ImportFailure(
        rawLine: rawLine ?? this.rawLine,
        reason: reason ?? this.reason,
        kind: kind ?? this.kind,
        subject: subject ?? this.subject,
      );

  /// Serialises the failure, raw line included.
  JsonMap toJson() => <String, Object?>{
        'rawLine': rawLine,
        'reason': reason,
        'kind': kind.name,
        'subject': subject,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImportFailure &&
          other.rawLine == rawLine &&
          other.reason == reason &&
          other.kind == kind &&
          other.subject == subject;

  @override
  int get hashCode => Object.hash(rawLine, reason, kind, subject);

  /// Never prints [rawLine] unredacted.
  @override
  String toString() => 'ImportFailure($redactedLine, $reason)';
}
