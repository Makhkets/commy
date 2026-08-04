import 'package:commy_domain/commy_domain.dart';
import 'package:flutter/foundation.dart' show immutable;

/// An import failure as it came back out of the database.
///
/// Distinct from the domain `ImportFailure` on purpose: the domain type carries
/// the raw line, credentials and all, because the parser has just produced it
/// in memory. What reaches the disk is only the redacted line, so a type that
/// came *from* the disk must not pretend it still has the original — a caller
/// holding a `StoredImportFailure` cannot accidentally re-import or re-log a
/// live credential, because it does not have one.
@immutable
class StoredImportFailure {
  /// Creates a stored failure.
  const StoredImportFailure({
    required this.id,
    required this.redactedLine,
    required this.reason,
    required this.createdAt,
  });

  /// Stable identifier.
  final String id;

  /// The offending line, credentials already blanked.
  final String redactedLine;

  /// Why it failed, in words the user can act on.
  final String reason;

  /// When the import ran.
  final DateTime createdAt;

  /// The domain view of this row.
  ///
  /// `rawLine` is the redacted text, which is all we have and all we want:
  /// re-reading a stored failure must never resurrect a credential.
  ImportFailure toDomain() =>
      ImportFailure(rawLine: redactedLine, reason: reason);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoredImportFailure &&
          other.id == id &&
          other.redactedLine == redactedLine &&
          other.reason == reason &&
          other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, redactedLine, reason, createdAt);

  @override
  String toString() => 'StoredImportFailure($id, $reason)';
}
