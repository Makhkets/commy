import 'package:commy_domain/commy_domain.dart';

/// Thrown inside the parsers when one link cannot be understood.
///
/// It never escapes the package: it becomes the `ImportFailure` the user
/// reads. [kind] and [subject] are what the app words for them, in their
/// language; [reason] is the English sentence the log keeps.
class LinkFormatException implements Exception {
  /// Creates the exception for a link that could not be read.
  const LinkFormatException(this.reason)
      : kind = ImportFailureKind.malformed,
        subject = null;

  /// A link missing something every server needs.
  const LinkFormatException.incomplete(this.reason)
      : kind = ImportFailureKind.incomplete,
        subject = null;

  /// A server that needs something the core cannot do; [subject] names it.
  const LinkFormatException.unsupported(this.reason, {this.subject})
      : kind = ImportFailureKind.unsupported;

  /// A link of a scheme no parser knows; [subject] is the scheme.
  const LinkFormatException.unsupportedScheme(this.reason, {this.subject})
      : kind = ImportFailureKind.unsupportedScheme;

  /// Something that is not a link to a server at all.
  const LinkFormatException.notALink(this.reason)
      : kind = ImportFailureKind.notALink,
        subject = null;

  /// Why the link could not be turned into a node, in English, for the log.
  final String reason;

  /// Why, as the app words it.
  final ImportFailureKind kind;

  /// What [kind] is about in particular, or `null`. Never a credential.
  final String? subject;

  /// The failure the user reads for [rawLine].
  ImportFailure toFailure(String rawLine) => ImportFailure(
        rawLine: rawLine,
        reason: reason,
        kind: kind,
        subject: subject,
      );

  @override
  String toString() => 'LinkFormatException($reason)';
}
